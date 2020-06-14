import macros, json
import ../iface

type
  Caller = ref object
    caller: proc(j: JsonNode): JsonNode

proc callerCall(caller: Caller, j: JsonNode): JsonNode {.inline.} =
  caller.caller(j)

proc serializeMethod(methodName: string, args: varargs[(string, JsonNode)]): JsonNode =
  result = %*{"method": methodName}
  for i in 0 .. args.high:
    result[args[i][0]] = args[i][1]

proc serializeArg[T](name: string, v: T): (string, JsonNode) = (name, %v)

proc parseJsonResult(T: typedesc, j: JsonNode): T =
  when T isnot void:
    j.to(T)

proc stripSinkFromArgType(t: NimNode): NimNode =
  result = t
  if result.kind == nnkBracketExpr and result.len == 2 and result[0].kind == nnkSym and $result[0] == "sink":
    result = result[1]

iterator arguments(formalParams: NimNode): tuple[idx: int, name, typ, default: NimNode] =
  formalParams.expectKind(nnkFormalParams)
  var iParam = 0
  for i in 1 ..< formalParams.len:
    let pp = formalParams[i]
    for j in 0 .. pp.len - 3:
      yield (iParam, pp[j], copyNimTree(stripSinkFromArgType(pp[^2])), pp[^1])
      inc iParam

macro genCaller(ifaceType: typedesc): untyped =
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


  echo "result: ", repr result


proc newJsonRPCCaller*(T: typedesc[Interface], caller: proc(j: JsonNode): JsonNode): T =
  genCaller(T)
  localIfaceImpl(T, Caller)
  echo "blabla"
  toT(Caller(caller: caller))
