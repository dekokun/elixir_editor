defmodule ElixirEditor do
  @moduledoc false

  def start(_type, _args) do

    :ets.new(:message_wall, [:set, :named_table, :public])
    dispatch = :cowboy_router.compile([
      {:_, [
        # cowboy_staticはパスマッチに対して、静的ファイルを読み込む
        # index.htmlを読み込む
        {"/", :cowboy_static, {:file, :filename.join(
          [:filename.dirname(:code.which(__MODULE__)),
            "..", "priv", "index.html"])}},
        {"/bundle.js", :cowboy_static, {:file, :filename.join(
          [:filename.dirname(:code.which(__MODULE__)),
            "..", "priv", "bundle.js"])}},
        {"/flex.css", :cowboy_static, {:file, :filename.join(
          [:filename.dirname(:code.which(__MODULE__)),
            "..", "priv", "flex.css"])}},
        # /websocketのリクエストをws_handlerに渡す
        {"/websocket", :MessageWallHandler, []}
      ]}
    ])
    {:ok, _} = :cowboy.start_http(:http, 100,
      [{:port, port()}],
      [
        {:env, [{:dispatch, dispatch}]}
      ])
    MessageWallSup.start_link()
  end

  @doc """
    iex(1)> ElixirEditor.stop(1)
    :ok
  """
  def stop(_State) do
    :ets.delete(:message_wall)
    :cowboy.stop_listener(:http)
    :ok
  end

  defp port() do
    case :os.getenv("PORT") do
      false ->
        case :application.get_env(:http_port) do
        {:ok, port} ->
          port
        :undefined ->
          8080
        end
      other ->
        :erlang.list_to_integer(other)
    end
  end
end
