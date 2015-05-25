defmodule MessageWallHandler do
  @behaviour :cowboy_websocket_handler

  def init(_, _, _) do
    {:upgrade, :protocol, :cowboy_websocket}
  end

  # websocket_init はwebsocket接続が開始された時に実行されます
  def websocket_init(_, req, _opts) do
    # プロセスをgproc pubsubに登録する
    :gproc_ps.subscribe(:l, :new_message)
    # stateを設定する
    ip = get_ip(req)
    {UserAgent, _Req} = :cowboy_req.header(<<"user-agent">>, req)
    state = %State{ip: ip, ua: UserAgent, room_id: 1}
    # WebSocketリクエストは長くなる可能性があるため
    # 不要なデータをReqから削除
    Req2 = :cowboy_req.compact(req)
    # 自動切断を10分に設定する（60万ミリ秒）
    {:ok, Req2, state, 600000, :hibernate}
  end

  # get_markdownメッセージの場合はメッセージのリストを返します
  def websocket_handle({:text, <<"\"get_markdown\"">>}, req, state) do
    room_id = state[:room_id]
    :io.format("get_markdownですよ~n")
    # 最新のメッセージを取得する
    Tuple = get_markdown(room_id)
    # メッセージをJiffyが変換できる形式に変更
    markdown = format_markdown(Tuple)
    :io.format("dataですよ ~w~n", [markdown])
    # JiffyでJsonレスポンスを生成
    jsonResponse = :jiffy.encode(%{
      <<"type">> => <<"all">>,
      <<"markdown">> => markdown
    })
    :io.format("responceですよ ~s~n", [jsonResponse])
    # JSONを返す
    {:reply, {:text, jsonResponse}, req, state}
  end
  # get_markdown以外のメッセージの扱い
  def websocket_handle({:text, text}, req, state) do
    room_id = state[:room_id]
    {[{<<"set_markdown">>, RawMarkdown}, {<<"from">>, fromGuid}|_]} = :jiffy.decode(text)

    markdown =
    if RawMarkdown === <<>> do
       ""
    else
      RawMarkdown
    end

    :io.format("~w~n", [markdown])
    save_message(RoomId, markdown)
    # gprocにイベントを公開し、
    # 全ての接続クライアントにwebsocket_info({gproc_ps_event, new_message, {RoomId, fromGuid}}, req, State)を呼び出します
    :gproc_ps.publish(:l, :new_message, {room_id, fromGuid})
    {:ok, req, state}
  end
  def websocket_handle({:binary, data}, req, state) do
    {:reply, {:binary, data}, req, state}
  end
  def websocket_handle(_Frame, req, state) do
    {:ok, req, state}
  end

  # websocket_infoは本プロセスにErlangメッセージが届いた時に実行されます
  # gprocからnew_messageメッセージの場合はそのメッセージをWebSocketに送信します
  def websocket_info({:gproc_ps_event, :new_message, {roomId, fromGuid}}, req, state) do
    rawMessage = get_markdown(roomId)
    # ETS結果をマップに変換
    :io.format("~w", [rawMessage])
    message = format_message(rawMessage)
    jsonResponse = :jiffy.encode(%{
      <<"from">> => fromGuid,
      <<"type">> => <<"all">>,
      <<"markdown">> => message
    })
    {:reply, {:text, jsonResponse}, req, state}
  end
  def websocket_info(_Info, req, state) do
    {:ok, req, state}
  end

  def websocket_terminate(_reason, _req, _state) do
    :ok
  end

  # 対応するmarkdownを取得する
  def get_markdown(id) do
    case :ets.lookup(:message_wall, id) do
      [] -> {id, <<"">>}
      [Tuple] -> Tuple
    end
  end

  # ETS結果メッセージをJiffyが変換できる形式に変更
  def format_markdown({_id, markdown}) do
    markdown
  end

  # ETS結果メッセージをJiffyが変換できる形式に変更
  def format_message({_key, markdown}) do
    :unicode.characters_to_binary(markdown)
  end

  # IPタプルを文字列に変換
  # format_ip({I1,I2,I3,I4}) ->
  #   io_lib:format("~w.~w.~w.~w",[I1,I2,I3,I4]);
  # format_ip(Ip) -> Ip.

  # erlangのdatetimeをISO8601形式に変換
  # iso8601(Time) ->
  #   {{Year, Month, Day},{Hour, Minut, Second}} = calendar:now_to_universal_time(Time),
  #   io_lib:format("~4..0B-~2..0B-~2..0BT~2..0B:~2..0B:~2..0BZ", [Year, Month, Day, Hour, Minut, Second]).

  # ETSにメッセージを保存する
  def save_message(key, markdown) do
    :ets.insert(:message_wall, {key, markdown})
  end

  # IP取得
  def get_ip(req) do
    # プロキシ経由対応
    case :cowboy_req.header(<<"x-real-ip">>, req) do
      {:undefined, _req} ->
        {{Ip, _port}, _req} = :cowboy_req.peer(req)
        Ip
      {Ip, _req} -> Ip
    end
  end
end