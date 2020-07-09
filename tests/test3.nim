import iface, json, unittest, asyncdispatch
import rpc/[json_router, json_caller]

iface MyInterface:
  proc bar(a: string = "hi"): Future[void]
  proc foo(yo: int, m: float = 5): Future[string]

iface MyInterfaceSemiSync:
  proc bar(a: string = "hi"): Future[void]
  proc foo(yo: int, m: float = 5): Future[string]
  proc fooSync(yo: int): string

type
  MyImpl = ref object

proc bar(t: MyImpl, a: string) {.async.} =
  await sleepAsync(5)
  echo "myimplbar: ", a

proc foo(t: MyImpl, yo: int, m: float): Future[string] {.async.} =
  await sleepAsync(5)
  echo "myimplfoo: ", yo
  return "Hello " & $yo

proc fooSync(t: MyImpl, yo: int): string =
  return "sync hello " & $yo

suite "async rpc":
  test "router":
    let i = MyImpl()
    let r = newAsyncJsonRPCRouter(MyInterfaceSemiSync(i))
    check waitFor(r.route(%*{"method": "bar", "a": "hello world"})).kind == JNull
    check waitFor(r.route(%*{"method": "foo", "yo": 123})).getStr() == "Hello 123"
    check waitFor(r.route(%*{"method": "fooSync", "yo": 123})).getStr() == "sync hello 123"

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
