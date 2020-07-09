import json, asyncfutures
import ./caller
import ../iface

type
  JsonMessageCaller[T] = object
    curMessage: JsonNode
    senderProc: proc(m: JsonNode): T

  SyncJsonMessageCaller = JsonMessageCaller[JsonNode]
  AsyncJsonMessageCaller = JsonMessageCaller[Future[JsonNode]]

template messageBegin*(c: JsonMessageCaller, messageName: string, messageIdx: int, numArgs: int) =
  c.curMessage = newJObject()
  c.curMessage["method"] = %messageName

template messageArg*[T](c: JsonMessageCaller, argName: string, argIdx: int, argValue: T) =
  c.curMessage[argName] = %argValue

proc parseJsonResult(T: typedesc, j: JsonNode): T =
  when T isnot void:
    j.to(T)

proc parseJsonResult[T](F: typedesc[Future[T]], j: Future[JsonNode]): F =
  result = newFuture[T]()
  let r = result
  j.addCallback() do():
    echo "Json future complete"
    # TODO: Handle errors
    when T isnot void:
      r.complete(parseJsonResult(T, j.read()))
    else:
      r.complete()

proc messageCall*(c: var JsonMessageCaller, ResultType: typedesc): ResultType =
  let r = c.senderProc(c.curMessage)
  c.curMessage = nil
  parseJsonResult(ResultType, r)

proc newJsonRPCCaller*(T: typedesc[Interface], caller: proc(j: JsonNode): JsonNode): T {.inline.} =
  newCaller(T, SyncJsonMessageCaller(senderProc: caller))

proc newAsyncJsonRPCCaller*(T: typedesc[Interface], caller: proc(j: JsonNode): Future[JsonNode]): T =
  newCaller(T, AsyncJsonMessageCaller(senderProc: caller))
