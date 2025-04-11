defmodule IbExExamples.MarketDepthConsumer do
  use GenServer

  alias IbEx.Client
  alias IbEx.Client.Messages.MarketDepth
  alias IbEx.Client.Messages.MatchingSymbols

  defstruct client_pid: nil,
            market: nil,
            contract: nil,
            levels: nil,
            bids: [],
            asks: [],
            trace_messages: false

  @message_side_to_state %{
    "bid" => :bids,
    "ask" => :asks
  }

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  def get_state(pid) do
    GenServer.call(pid, :get_state)
  end

  @impl true
  def init(opts) do
    market = Keyword.get(opts, :market, "TSLA")
    levels_count = Keyword.get(opts, :levels, 25)
    client_pid = Keyword.get(opts, :client_pid, nil)
    trace_messages = Keyword.get(opts, :trace_messages, false)

    levels =
      Enum.map(0..(levels_count - 1), fn _ ->
        %{"market_maker" => "", "price" => "", "size" => ""}
      end)

    continuation =
      if is_nil(client_pid) do
        {:continue, :start_client}
      else
        {:continue, :fetch_market_contract}
      end

    Owl.LiveScreen.add_block(:orderbook, render: &livescreen_renderer/1)

    state = %__MODULE__{
      client_pid: client_pid,
      market: market,
      levels: levels_count,
      bids: levels,
      asks: levels,
      trace_messages: trace_messages
    }

    {:ok, state, continuation}
  end

  @impl true
  def handle_continue(:start_client, state) do
    case Client.start_link(trace_messages: state.trace_messages) do
      {:ok, pid} ->
        Process.send_after(self(), :fetch_market_contract, 2000)
        {:noreply, %{state | client_pid: pid}}

      _ ->
        {:stop, "client_connection_error", state}
    end
  end

  @impl true
  def handle_continue(:fetch_market_contract, state) do
    {:ok, msg} = IbEx.Client.Messages.MatchingSymbols.Request.new(state.market)
    Client.send_request(state.client_pid, msg)

    {:noreply, state}
  end

  @impl true
  def handle_continue(:subscribe_to_market_depth, state) do
    {:ok, msg} = MarketDepth.RequestData.new(state.contract, state.levels)
    Client.send_request(state.client_pid, msg)

    {:noreply, state}
  end

  @impl true
  def handle_continue(:update_orderbook, state) do
    Owl.LiveScreen.update(:orderbook, {state.bids, state.asks})
    {:noreply, state}
  end

  @impl true
  def handle_cast({:message_received, %MatchingSymbols.SymbolSamples{} = msg}, state) do
    contract =
      Enum.find(
        msg.contracts,
        &(&1.contract.symbol == state.market && &1.contract.security_type == "STK")
      )
      |> Map.get(:contract)

    {:noreply, %{state | contract: contract}, {:continue, :subscribe_to_markete_depth}}
  end

  @impl true
  def handle_cast({:message_received, %MarketDepth.L2DataMultiple{} = msg}, state) do
    side_name = @message_side_to_state[msg.side]

    side = Map.get(state, side_name)

    new_side =
      put_in(
        side,
        [Access.at(msg.position)],
        %{
          "#{side_name}_MM" => msg.market_maker,
          "#{side_name}_Size" => msg.size,
          "#{side_name}_Price" => msg.price
        }
      )

    {:noreply, Map.put(state, side_name, new_side), {:continue, :update_orderbook}}
  end

  @impl true
  def handle_info(:fetch_market_contract, state) do
    {:noreply, state, {:continue, :fetch_market_contract}}
  end

  @columns_order [
    "Timestamp",
    "Price",
    "Size",
    "Exchange",
    "Conditions",
    "bids_MM",
    "bids_Size",
    "bids_Price",
    "asks_Price",
    "asks_Size",
    "asks_MM"
  ]

  def compare(term1, term2) do
    case Enum.find_index(@columns_order, &(&1 == term1)) >
           Enum.find_index(@columns_order, &(&1 == term2)) do
      true -> :gt
      false -> nil
    end
  end

  defp livescreen_renderer(data) do
    case data do
      nil ->
        ""

      {bids, asks} ->
        bid_levels = extract_prices(bids, "bids", :desc)
        ask_levels = extract_prices(asks, "asks", :asc)

        {bids, asks}
        |> merge_quotes()
        |> Owl.Table.new(
          render_cell: [
            header: &header_renderer/1,
            body: &body_renderer(&1, {bid_levels, ask_levels})
          ],
          sort_columns: {:asc, __MODULE__}
        )
    end
  end

  defp merge_quotes({bids, asks}) do
    printable_bids =
      Enum.map(bids, fn level ->
        Enum.reduce(level, %{}, fn {k, v}, acc -> Map.put(acc, k, to_string(v)) end)
      end)

    printable_asks =
      Enum.map(asks, fn level ->
        Enum.reduce(level, %{}, fn {k, v}, acc -> Map.put(acc, k, to_string(v)) end)
      end)

    printable_bids
    |> Enum.zip(printable_asks)
    |> Enum.map(fn {bid, ask} -> Map.merge(bid, ask) end)
  end

  defp header_renderer(term) do
    Owl.Data.tag(term, :white)
  end

  @quote_level_colors [
    [:black, :yellow_background],
    [:white, :green_background],
    [:white, :blue_background],
    [:white, :red_background]
  ]

  defp body_renderer(term, quote_levels) do
    colors = determine_color(term, quote_levels)
    Owl.Data.tag(term, colors)
  end

  defp determine_color(term, {bid_levels, ask_levels}) do
    index =
      if term in bid_levels do
        Enum.find_index(bid_levels, &(&1 == term))
      else
        Enum.find_index(ask_levels, &(&1 == term))
      end

    if is_nil(index) do
      [:white]
    else
      Enum.at(@quote_level_colors, Integer.mod(index, length(@quote_level_colors)))
    end
  end

  defp extract_prices(levels, key, sort_direction) do
    levels
    |> Enum.map(&Map.get(&1, "#{key}_Price"))
    |> Enum.uniq()
    |> Enum.sort(sort_direction)
    |> Enum.map(&to_string/1)
  end
end
