import macros
import ../iface
import ./private/utils

## TMessageCaller should define the following methods:
## proc messageBegin(caller, messageName: string, messageIdx: int, numArgs: int)
## proc messageArg[T](caller, argName: string, argIdx: int, argValue: T)
## proc messageCall(caller, ResultType: typedesc): ResultType

type
  Caller[TMessageCaller] = ref object
    messageCaller: TMessageCaller

template callerMessageBegin(caller: Caller, messageName: string, messageIdx: int, numArgs: int) =
  mixin messageBegin
  messageBegin(caller.messageCaller, messageName, messageIdx, numArgs)

template callerMessageArg[T](caller: Caller, argName: string, argIdx: int, argValue: T) =
  mixin messageArg
  messageArg(caller.messageCaller, argName, argIdx, argValue)

template callerMessageCall(caller: Caller): auto =
  mixin messageCall
  when compiles(result):
    messageCall(caller.messageCaller, typeof(result))
  else:
    messageCall(caller.messageCaller, void)

macro genCaller(ifaceType: typedesc): untyped =
  let decl = getInterfaceDecl(ifaceType)
  let thisid = ident"this"
  result = newNimNode(nnkStmtList)
  for messageIdx, p in decl:
    let pp = copyNimTree(p)
    pp.params.insert(1, newIdentDefs(thisid, bindSym"Caller"))

    let argSerializingCode = newNimNode(nnkStmtList)
    var numArgs = 0
    for i, name, typ, def in arguments(p.params):
      inc numArgs
      argSerializingCode.add newCall(bindSym"callerMessageArg", thisid, newLit($name), newLit(i), name)

    let ms = newNimNode(nnkStmtList)
    ms.add newCall(bindSym"callerMessageBegin", thisid, newLit($p.name), newLit(messageIdx), newLit(numArgs))
    ms.add(argSerializingCode)
    ms.add newCall(bindSym"callerMessageCall", thisid)
    pp.body = ms

    result.add(pp)

proc newCaller*[TMessageCaller](T: typedesc[Interface], caller: TMessageCaller): T =
  genCaller(T)
  localIfaceConvert(T, Caller[TMessageCaller](messageCaller: caller))
