import macros, json
import ../../iface
import ./utils

type
  Caller*[T] = ref object
    caller*: proc(j: JsonNode): T

proc callerCall[T](caller: Caller[T], j: JsonNode): T {.inline.} =
  caller.caller(j)

proc serializeMethod(methodName: string, args: varargs[(string, JsonNode)]): JsonNode =
  result = %*{"method": methodName}
  for i in 0 .. args.high:
    result[args[i][0]] = args[i][1]

proc serializeArg[T](name: string, v: T): (string, JsonNode) = (name, %v)

proc parseJsonResult(T: typedesc, j: JsonNode): T =
  when T isnot void:
    j.to(T)

macro genCaller*(ifaceType: typedesc): untyped =
  let decl = getInterfaceDecl(ifaceType)
  let thisid = ident"this"
  result = newNimNode(nnkStmtList)
  for p in decl:
    let pp = copyNimTree(p)
    pp.params.insert(1, newIdentDefs(thisid, bindSym"Caller"))
    let ms = newCall(bindSym"serializeMethod", newLit($p.name))
    for i, name, typ, def in arguments(p.params):
      ms.add newCall(bindSym"serializeArg", newLit($name), name)

    var retType = pp.params[0]
    if retType.kind == nnkEmpty: retType = ident"void"
    retType = newCall("type", retType) # Workaround for nim bug
    pp.body = newCall(bindSym"parseJsonResult", retType, newCall(bindSym"callerCall", thisid, ms))
    result.add(pp)
