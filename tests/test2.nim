import iface, json, unittest
import rpc/[json_router, json_caller]

iface MyInterface:
  proc bar(a: string = "hi")
  proc foo(yo: int, m: float = 5): string

type
  MyImpl = ref object

proc bar(t: MyImpl, a: string) =
  echo "myimplbar: ", a

proc foo(t: MyImpl, yo: int, m: float): string =
  echo "myimplfoo: ", yo
  return "Hello " & $yo

suite "rpc":
  test "router":
    let i = MyImpl()
    let r = newJsonRPCRouter(MyInterface(i))
    check r.route(%*{"method": "bar", "a": "hello world"}).kind == JNull
    check r.route(%*{"method": "foo", "yo": 123}).getStr() == "Hello 123"

  test "caller":
    var c = newJsonRpcCaller(MyInterface) do(j: JsonNode) -> JsonNode:
      check:
        j["method"].getStr == "bar"
        j["a"].getStr == "hi"
      newJNull()

    c.bar()

    c = newJsonRpcCaller(MyInterface) do(j: JsonNode) -> JsonNode:
      check:
        j["method"].getStr == "foo"
        j["yo"].getInt == 456
        $(j["m"].getFloat) == "5.0"
      %"ok"

    check c.foo(456) == "ok"
