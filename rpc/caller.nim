import macros, json
import ./private/caller_base
import ../iface

type
  SyncCaller = Caller[JsonNode]

proc newJsonRPCCaller*(T: typedesc[Interface], caller: proc(j: JsonNode): JsonNode): T =
  genCaller(T)
  localIfaceConvert(T, SyncCaller(caller: caller))
