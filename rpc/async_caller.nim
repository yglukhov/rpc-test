import macros, json, asyncdispatch
import ./private/caller_base
import ../iface
import ../iface/async

type
  AsyncCaller = Caller[Future[JsonNode]]

proc newAsyncJsonRPCCaller*(T: typedesc[Interface], caller: proc(j: JsonNode): JsonNode): T =
  genCaller(T)
  localIfaceConvert(T, SyncCaller(caller: caller))
