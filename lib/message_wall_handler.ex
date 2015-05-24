defmodule MessageWallHandler do
  @behaviour :cowboy_websocket_handler

  def init(_, _, _) do
    {:upgrade, :protocol, :cowboy_websocket}
  end

  # websocket_init はwebsocket接続が開始された時に実行されます
  def websocket_init(_, Req, _Opts) do
    # プロセスをgproc pubsubに登録する
    :gproc_ps.subscribe(:l, :new_message)
    # stateを設定する
    Ip = get_ip(Req)
    {UserAgent, _Req} = :cowboy_req.header(<<"user-agent">>, Req)
    state = %State{ip: Ip, ua: UserAgent, room_id: 1}
    # WebSocketリクエストは長くなる可能性があるため
    # 不要なデータをReqから削除
    Req2 = :cowboy_req.compact(Req)
    # 自動切断を10分に設定する（60万ミリ秒）
    {:ok, Req2, state, 600000, :hibernate}
  end

  # get_markdownメッセージの場合はメッセージのリストを返します
  def websocket_handle({:text, <<"\"get_markdown\"">>}, Req, state) do
    room_id = state[:room_id]
    :io.format("get_markdownですよ~n")
    # 最新のメッセージを取得する
    Tuple = get_markdown(room_id)
    # メッセージをJiffyが変換できる形式に変更
    Markdown = format_markdown(Tuple)
    :io.format("dataですよ ~w~n", [Markdown])
    # JiffyでJsonレスポンスを生成
    JsonResponse = :jiffy.encode(%{
      <<"type">> => <<"all">>,
      <<"markdown">> => Markdown
    })
    :io.format("responceですよ ~s~n", [JsonResponse])
    # JSONを返す
    {:reply, {:text, JsonResponse}, Req, state}
  end

  # get_markdown以外のメッセージの扱い
  def websocket_handle({:text, Text}, Req, state) do
    room_id = state[:room_id]
    {[{<<"set_markdown">>, RawMarkdown}, {<<"from">>, FromGuid}|_]} = :jiffy.decode(Text)

    markdown =
    if RawMarkdown === <<>> do
       ""
    else
      RawMarkdown
    end

    :io.format("~w~n", [markdown])
    save_message(RoomId, markdown)
    # gprocにイベントを公開し、
    # 全ての接続クライアントにwebsocket_info({gproc_ps_event, new_message, {RoomId, FromGuid}}, Req, State)を呼び出します
    :gproc_ps.publish(:l, :new_message, {room_id, FromGuid})
    {:ok, Req, state}
  end


  def websocket_handle({:binary, Data}, Req, state) do
    {:reply, {:binary, Data}, Req, state}
  end
  def websocket_handle(_Frame, Req, state) do
    {:ok, Req, state}
  end

  # websocket_infoは本プロセスにErlangメッセージが届いた時に実行されます
  # gprocからnew_messageメッセージの場合はそのメッセージをWebSocketに送信します
  def websocket_info({:gproc_ps_event, :new_message, {RoomId, FromGuid}}, Req, state) do
    RawMessage = get_markdown(RoomId)
    # ETS結果をマップに変換
    :io.format("~w", [RawMessage])
    Message = format_message(RawMessage)
    JsonResponse = :jiffy.encode(%{
      <<"from">> => FromGuid,
      <<"type">> => <<"all">>,
      <<"markdown">> => Message
    })
    {:reply, {:text, JsonResponse}, Req, state}
  end
  def websocket_info(_Info, Req, state) do
    {:ok, Req, state}
  end

  def websocket_terminate(_Reason, _Req, _State) do
    :ok
  end

  # 対応するmarkdownを取得する
  def get_markdown(Id) do
    case :ets.lookup(:message_wall, Id) do
      [] -> {Id, <<"">>}
      [Tuple] -> Tuple
    end
  end

  # ETS結果メッセージをJiffyが変換できる形式に変更
  def format_markdown({_Id, Markdown}) do
    Markdown
  end

  # ETS結果メッセージをJiffyが変換できる形式に変更
  def format_message({_Key, Markdown}) do
    :unicode.characters_to_binary(Markdown)
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
  def save_message(Key, Markdown) do
    :ets.insert(:message_wall, {Key, Markdown})
  end

  # IP取得
  def get_ip(Req) do
    # プロキシ経由対応
    case :cowboy_req.header(<<"x-real-ip">>, Req) do
      {:undefined, _Req} ->
        {{Ip, _Port}, _Req} = :cowboy_req.peer(Req)
        Ip
      {Ip, _Req} -> Ip
    end
  end
end