defmodule Tapper.Tracer.Trace do
  @moduledoc "Tracer internal state, and functions to convert this to protocol spans (`Tapper.Protocol.Span`)"

  alias Tapper.Timestamp

  @typedoc "Tracer state: the state of a single trace session."
  defstruct [
    :config,        # configuration from supervisor
    :trace_id,      # root trace_id
    :span_id,       # root span id
    :parent_id,     # parent of trace, or :root if new root trace
    :sample,        # we are sampling this trace
    :debug,         # we are debugging this trace

    :spans,         # map of spans in this trace
    :timestamp,     # start of trace
    :end_timestamp, # end of trace
    :last_activity, # last time a span was started, ended or updated
    :ttl,           # time to live in ms, past last_activity
    :async          # this trace will finish asynchronously
  ]

  @type trace :: %__MODULE__{
    trace_id: Tapper.TraceId.t,
    span_id: Tapper.SpanId.t,
    parent_id: Tapper.SpanId.t | :root,
    spans: %{required(Tapper.SpanId.t) => Tapper.Tracer.Trace.SpanInfo.t},
    config: map(),
    sample: boolean(),
    debug: boolean(),
    timestamp: Timestamp.t,
    end_timestamp: Timestamp.t,
    last_activity: Timestamp.t,
    ttl: integer(),
    async: nil | true
  }
  @type t :: trace

  defmodule SpanInfo do
    @moduledoc false
    alias Tapper.Tracer.Trace.Annotation
    alias Tapper.Tracer.Trace.BinaryAnnotation

    defstruct [
      :name,
      :id,
      :parent_id,
      :shared,
      :start_timestamp,
      :end_timestamp,
      :annotations,
      :binary_annotations
    ]

    @typedoc "A span inside a trace"
    @type t :: %__MODULE__{
      name: String.t,
      id: Tapper.SpanId.t,
      parent_id: Tapper.SpanId.t,
      shared: boolean, # did we start this span, or inherit it from another process?
      start_timestamp: Timestamp.t,
      end_timestamp: Timestamp.t,
      annotations: [Annotation.t],
      binary_annotations: [BinaryAnnotation.t]
    }
  end

  defmodule Annotation do
    @moduledoc false

    @typedoc "an event annotation"
    defstruct [
      :timestamp,
      :value,
      :host
    ]

    @type t :: %__MODULE__{
      timestamp: Timestamp.t,
      value: atom() | String.t,
      host: Tapper.Endpoint.t | nil
    }

    def new(value, timestamp, endpoint = %Tapper.Endpoint{}) when is_tuple(timestamp) do
      %__MODULE__{
        value: value,
        timestamp: timestamp,
        host: endpoint
      }
    end

    def new(value, timestamp) when is_tuple(timestamp) do
      %__MODULE__{
        value: value,
        timestamp: timestamp
      }
    end
  end

  defmodule BinaryAnnotation do
    @moduledoc false

    @typedoc "a binary annotation"
    defstruct [
      :key,
      :value,
      :annotation_type,
      :host # optional
    ]

    @type annotation_type :: :string | :bool | :i16 | :i32 | :i64 | :double | :bytes

    @type t :: %__MODULE__{
      key: atom() | String.t,
      value: any(),
      annotation_type: annotation_type(),
      host: Tapper.Endpoint.t | nil
    }

    @types [:string, :bool, :i16, :i32, :i64, :double, :bytes]

    def new(key, value, type, endpoint = %Tapper.Endpoint{}) when type in @types do
      %__MODULE__{
        key: key,
        value: value,
        annotation_type: type,
        host: endpoint
      }
    end

    def new(key, value, type) when type in @types do
      %__MODULE__{
        key: key,
        value: value,
        annotation_type: type,
      }
    end
  end

  @doc false
  @spec endpoint_from_config(map()) :: Tapper.Endpoint.t
  def endpoint_from_config(%{host_info: %{ip: ip, system_id: system_id}}) do
    %Tapper.Endpoint{
        service_name: system_id,
        ip: ip,
        port: 0
    }
  end

  @doc false
  def has_annotation?(trace = %__MODULE__{}, span_id, value), do: has_annotation?(trace.spans[span_id], value)

  @doc false
  def has_annotation?(nil, _value), do: false

  def has_annotation?(%__MODULE__.SpanInfo{annotations: annotations}, value) do
    Enum.any?(annotations, fn(annotation) -> annotation.value === value end)
  end

  @doc false
  def parents_of(trace = %__MODULE__{}, span_id) when is_integer(span_id) do
    span = trace.spans[span_id]
    Enum.reverse(parents_of(trace, span, []))
  end

  defp parents_of(_trace, %__MODULE__.SpanInfo{parent_id: :root}, parent_ids) do
    parent_ids
  end
  defp parents_of(trace, %__MODULE__.SpanInfo{parent_id: parent_id}, parent_ids) do
    parent_span = trace.spans[parent_id]
    parents_of(trace, parent_span, [parent_id | parent_ids])
  end


end
