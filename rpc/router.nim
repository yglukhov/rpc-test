import macros, json
import ../iface
import ./private/utils

type
  JsonRPCRouter* = ref object of RootObj
    dispatch: proc(r: JsonRPCRouter, j: JsonNode): JsonNode {.nimcall.}

proc parseJsonArg(typ: typedesc, name: string, j: JsonNode): typ =
  let c = j{name}
  if unlikely c.isNil:
    raise newException(ValueError, "Required parameter is missing: " & name)
  c.to(typ)

proc parseJsonArg(typ: typedesc, name: string, def: typ, j: JsonNode): typ =
  let c = j{name}
  if c.isNil:
    def
  else:
    c.to(typ)

template convertToJson[T](v: T): JsonNode =
  when T is void:
    v
    newJNull()
  else:
    %(v)

proc unknownMethodError(methodName: string): JsonNode =
  raise newException(ValueError, "Unknown method: " & methodName)

macro genDispatcherBody(theT: typedesc, o: typed, j: JsonNode, methodName: string): untyped =
  let decl = getInterfaceDecl(theT)
  result = newTree(nnkCaseStmt, methodName)
  for p in decl:
    let br = newTree(nnkOfBranch, newLit($p.name))
    let theCall = newCall(p.name, o)
    for i, name, typ, def in arguments(p.params):
      if def.kind == nnkEmpty:
        theCall.add newCall(bindSym"parseJsonArg", typ, newLit($name), j)
      else:
        theCall.add newCall(bindSym"parseJsonArg", typ, newLit($name), def, j)
    br.add newCall(bindSym"convertToJson", theCall)
    result.add(br)

  result.add newTree(nnkElse, newCall(bindSym"unknownMethodError", methodName))

proc dispatchJsonToInterface(o: Interface, methodName: string, j: JsonNode): JsonNode =
  genDispatcherBody(type(o), o, j, methodName)

proc newJsonRPCRouter*(i: Interface): JsonRPCRouter =
  type
    I = typeof(i)
    Router = ref object of JsonRPCRouter
      obj: I
  let r = Router(obj: i)
  r.dispatch = proc(r: JsonRPCRouter, j: JsonNode): JsonNode {.nimcall.} =
    dispatchJsonToInterface(Router(r).obj, j["method"].getStr(), j)

  result = r

proc route*(r: JsonRPCRouter, j: JsonNode): JsonNode {.inline.} = r.dispatch(r, j)
