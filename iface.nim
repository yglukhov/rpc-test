import macros, tables

type
  Interface*[VTable] = object
    private_vTable*: ptr VTable
    private_obj*: RootRef

  CTWrapper[T] = ref object of RootRef
    v: T

proc getVTable(VTable: typedesc, T: typedesc): ptr VTable =
  mixin initVTable
  var tab {.global.} = initVTable(VTable, T)
  addr tab

template unpackObj[T](f: RootRef, res: var T) =
  when nimvm:
    res = CTWrapper[T](f).v
  else:
    res = cast[T](f)

proc packObj[T](v: T): RootRef {.inline.} =
  when nimvm:
    result = CTWrapper[T](v: v)
  else:
    result = cast[RootRef](v)

macro checkRequiredMethod(call: typed, typ: typed): untyped =
  let impl = getImpl(call[0])
  if impl.kind == nnkProcDef and impl.params.len > 1 and impl.params[1][^2] == typ:
    error "Object does not implement required interface method: " & repr(call)
  result = call

macro iface*(name: untyped, body: untyped): untyped =
  result = newNimNode(nnkStmtList)

  let iName = ident($name)
  let converterName = ident("to" & $name)
  let vTableTypeName = ident("InterfaceVTable" & $name)
  var vTableType = newNimNode(nnkRecList)
  let vTableConstr = newTree(nnkObjConstr, vTableTypeName)
  let genericT = ident("T")
  let functions = newNimNode(nnkStmtList)
  let mixins = newNimNode(nnkStmtList)
  let upackedThis = ident"unpackedThis"

  for i, p in body:
    p.expectKind(nnkProcDef)
    let pName = $p.name
    mixins.add(newTree(nnkMixinStmt, p.name))
    let pt = newTree(nnkProcTy, p.params, newEmptyNode())
    pt.addPragma(ident"nimcall")
    pt[0].insert(1, newIdentDefs(ident"this", ident"RootRef"))
    let fieldName = ident("<" & $i & ">" & $p.name)
    vTableType.add(newIdentDefs(fieldName, pt))

    let lambdaCall = newCall(p.name)
    lambdaCall.add(upackedThis)

    let vCall = newTree(nnkCall, newTree(nnkDotExpr, newTree(nnkDotExpr, ident"this", ident"private_vTable"), fieldName))
    vCall.add(newTree(nnkDotExpr, ident"this", ident"private_obj"))

    for a in 1 ..< p.params.len:
      let par = p.params[a]
      for b in 0 .. par.len - 3:
        lambdaCall.add(par[b])
        vCall.add(par[b])

    let lambdaBody = quote do:
      var `upackedThis`: `genericT`
      unpackObj(this, `upackedThis`)
      checkRequiredMethod(`lambdaCall`, `iName`)

    let lam = newTree(nnkLambda, newEmptyNode(), newEmptyNode(), newEmptyNode(), pt[0], newEmptyNode(), newEmptyNode(), lambdaBody)
    # lam.addPragma(newTree(nnkExprColonExpr, ident"stackTrace", ident"off"))

    vTableConstr.add(newTree(nnkExprColonExpr, fieldName, lam))

    p.params.insert(1, newIdentDefs(ident"this", iName))

    p.body = vCall
    p.addPragma(ident"inline")
    p.addPragma(newTree(nnkExprColonExpr, ident"stackTrace", ident"off"))

    functions.add(p)

  vTableType = newTree(nnkTypeSection, newTree(nnkTypeDef, vTableTypeName, newEmptyNode(), newTree(nnkObjectTy, newEmptyNode(), newEmptyNode(), vTableType)))

  result.add quote do:
    `vTableType`
    type
      `iName` = Interface[`vTableTypeName`]
    proc initVTable(t: typedesc[`vTableTypeName`], `genericT`: typedesc): `vTableTypeName` =
      `mixins`
      `vTableConstr`
    `functions`
    converter `converterName`[T: ref](a: T): `iName` {.inline.} =
      when T is `iName`:
        a
      else:
        `iName`(private_vTable: getVTable(`iName`.VTable, T), private_obj: packObj(a))
  echo repr result

iterator interfaceProcs*(t: NimNode): (string, NimNode) =
  let r = getTypeImpl(t)[1].getTypeImpl()[2]
  for n in r:
    let fullName = $n[0]
    let prettyName = fullName[fullName.find('>') + 1 .. ^1]
    yield (prettyName, n[1])

# proc getInterfaceProcs(t: NimNode): NimNode =
#   result = getTypeImpl(t)[1].getTypeImpl()[2]

# macro doo(a: typed) =
#   let procs = getInterfaceProcs(a)
#   echo repr(procs)

