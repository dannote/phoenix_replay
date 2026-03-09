defmodule PhoenixReplay.Recording do
  @moduledoc """
  A recorded LiveView session.

  Contains the initial state and a timeline of events with assigns deltas,
  enough to reconstruct what the user saw at any point.
  """

  defstruct [
    :id,
    :view,
    :url,
    :params,
    :session,
    :connected_at,
    events: []
  ]

  @type event_type :: :mount | :event | :handle_params | :info | :assigns
  @type event :: {non_neg_integer(), event_type(), map()}

  @type t :: %__MODULE__{
          id: binary(),
          view: module(),
          url: binary() | nil,
          params: map(),
          session: map(),
          connected_at: integer(),
          events: [event()]
        }

  @doc """
  Replays events up to `index` and returns the accumulated assigns map.
  """
  @spec accumulated_assigns(t(), non_neg_integer()) :: map()
  def accumulated_assigns(%__MODULE__{events: events}, index) do
    events
    |> Enum.take(index + 1)
    |> Enum.reduce(%{}, fn
      {_, :mount, %{assigns: a}}, _acc -> a
      {_, :assigns, %{delta: delta}}, acc -> Map.merge(acc, delta)
      _, acc -> acc
    end)
  end
end
