import macros, json
import ../iface
import ./private/utils

## TMessageReader should define the following methods:
## proc messageNext(reader, T: typedesc[Interface]): int # returns method index in Interface
## proc messageArg(reader, ArgType: typedesc, argIdx: int, argName: string): ArgType
## proc messageArg(reader, ArgType: typedesc, argIdx: int, argName: string, defaultValue: ArgType): ArgType
## proc messageResult[T](reader, ResultType: typedesc, value: T): ResultType

type
  Router*[TResult] = ref object of RootObj
    dispatch: proc(r: Router[TResult]): TResult {.nimcall.}

  RouterWithReader*[TResult, TMessageReader] = ref object of Router[TResult]
    reader*: TMessageReader

proc unknownMethodError(RetType: typedesc): RetType =
  assert(false, "Internal error")

macro genDispatcherBody(interfaceType, retType: typedesc, o, reader: typed): untyped =
  let decl = getInterfaceDecl(interfaceType)
  result = newTree(nnkCaseStmt, newCall("messageNext", reader, interfaceType))
  for methodIdx, p in decl:
    let br = newTree(nnkOfBranch, newLit(methodIdx))
    let theCall = newCall(p.name, o)
    for i, name, typ, def in arguments(p.params):
      if def.kind == nnkEmpty:
        theCall.add newCall("messageArg", reader, typ, newLit(i), newLit($name))
      else:
        theCall.add newCall("messageArg", reader, typ, newLit(i), newLit($name), def)
    br.add newCall("messageResult", reader, retType, theCall)
    result.add(br)

  result.add newTree(nnkElse, newCall(bindSym"unknownMethodError", retType))

proc dispatchNextMessageToInterface[TMessageReader](TResult: typedesc, o: Interface, reader: TMessageReader): TResult {.inline.} =
  return genDispatcherBody(type(o), TResult, o, reader)

proc newRouter*[TMessageReader](i: Interface, TResult: typedesc, reader: TMessageReader): RouterWithReader[TResult, TMessageReader] =
  type
    I = typeof(i)
    R = typeof(result)
    RouterInst = ref object of R
      obj: I
  let r = RouterInst(reader: reader, obj: i)
  r.dispatch = proc(r: Router[TResult]): TResult {.nimcall.} =
    let r = RouterInst(r)
    dispatchNextMessageToInterface(TResult, r.obj, r.reader)

  result = r

proc dispatchNextMessage*[TResult](r: Router[TResult]): TResult =
  r.dispatch(r)
