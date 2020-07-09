import iface, json, unittest, asyncdispatch
import rpc/[router, json_caller]

iface MyInterface:
  proc bar(a: string = "hi"): Future[void]
  proc foo(yo: int, m: float = 5): Future[string]

type
  MyImpl = ref object

proc bar(t: MyImpl, a: string) {.async.} =
  echo "myimplbar: ", a

proc foo(t: MyImpl, yo: int, m: float): Future[string] {.async.} =
  echo "myimplfoo: ", yo
  return "Hello " & $yo

suite "async rpc":
  # test "router":
  #   let i = MyImpl()
  #   let r = newJsonRPCRouter(MyInterface(i))
  #   check r.route(%*{"method": "bar", "a": "hello world"}).kind == JNull
  #   check r.route(%*{"method": "foo", "yo": 123}).getStr() == "Hello 123"

  test "caller":
    var c = newAsyncJsonRpcCaller(MyInterface) do(j: JsonNode) -> Future[JsonNode] {.async.}:
      check:
        j["method"].getStr == "bar"
        j["a"].getStr == "hi"
      await sleepAsync(5)
      return newJNull()

    waitFor c.bar()

    c = newAsyncJsonRpcCaller(MyInterface) do(j: JsonNode) -> Future[JsonNode] {.async.}:
      await sleepAsync(5)
      check:
        j["method"].getStr == "foo"
        j["yo"].getInt == 456
        $(j["m"].getFloat) == "5.0"
      return %"ok"

    check (waitFor c.foo(456)) == "ok"
