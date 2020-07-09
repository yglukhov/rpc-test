import macros, json, asyncfutures
import ./router
import ../iface

type
  JsonRPCRouter* = RouterWithReader[JsonNode, JsonReader]
  AsyncJsonRPCRouter* = RouterWithReader[Future[JsonNode], JsonReader]

  JsonReader = object
    nextMessage: JsonNode

###################
# Private stuff
#

proc messageNext*(reader: JsonReader, T: typedesc[Interface]): int =
  let m = reader.nextMessage["method"].getStr()
  result = ifaceFindMethod(T, m)
  if result == -1:
    raise newException(ValueError, "Unrecognized method " & m)

proc messageArg*(reader: JsonReader, ArgType: typedesc, argIdx: int, argName: string): ArgType =
  let c = reader.nextMessage{argName}
  if unlikely c.isNil:
    raise newException(ValueError, "Required parameter is missing: " & argName)
  c.to(ArgType)

proc messageArg*(reader: JsonReader, ArgType: typedesc, argIdx: int, argName: string, defaultValue: ArgType): ArgType =
  let c = reader.nextMessage{argName}
  if c.isNil:
    defaultValue
  else:
    c.to(ArgType)

template messageResult*[T](reader: JsonReader, ResultType: typedesc[JsonNode], value: T): JsonNode =
  when T is void:
    value
    newJNull()
  else:
    %(value)

template messageResult*[T](reader: JsonReader, ResultType: typedesc[Future[JsonNode]], value: T): Future[JsonNode] =
  let res = newFuture[JsonNode]()
  when T is Future:
    value.addCallback do(f: T) {.nimcall.}:
      if unlikely f.failed:
        res.fail(f.error)
      else:
        res.complete(messageResult(reader, JsonNode, f.read()))
  else:
    res.complete(messageResult(reader, JsonNode, value))
  res

# End of private stuff
########################

proc newJsonRPCRouter*(i: Interface): JsonRPCRouter =
  newRouter(i, JsonNode, JsonReader())

proc newAsyncJsonRPCRouter*(i: Interface): AsyncJsonRPCRouter =
  newRouter(i, Future[JsonNode], JsonReader())

proc route*(r: JsonRPCRouter, j: JsonNode): JsonNode {.inline.} =
  r.reader.nextMessage = j
  result = r.dispatchNextMessage()
  r.reader.nextMessage = nil

proc route*(r: AsyncJsonRPCRouter, j: JsonNode): Future[JsonNode] {.inline.} =
  r.reader.nextMessage = j
  result = r.dispatchNextMessage()
  r.reader.nextMessage = nil
