import iface, chronos, macros

type
  RpcServer* = ref object of RootObj
    streamServer: StreamServer

  RpcServerImpl[T] = ref object of RpcServer
    obj: T

  RpcConnection = ref object
    send: proc(msg: seq[byte]): Future[void]
    handler: proc(d: ptr BufReader, s: ptr BufWriter): Future[void]

  BufReader = object
    a, b: ptr byte
  
  BufWriter = object
    data: seq[byte]

var commonAddress = initTAddress("/tmp/nim_rpc_socket")

proc read(b: ptr BufReader, T: typedesc): T =
  if cast[uint](b.b) - cast[uint](b.a) < uint(sizeof(T)):
    raise newException(Exception, "Buffer underflow")
  result = cast[ptr T](b.a)[]
  b.a = cast[ptr byte](cast[uint](b.a) + uint(sizeof(T)))

proc write[T](b: ptr BufWriter, v: T) =
  let i = b.data.len
  b.data.setLen(i + sizeof(v))
  cast[ptr T](addr b.data[i])[] = v

proc initBufReader(a: openarray[byte]): BufReader =
  let s = unsafeAddr a[0]
  let e = cast[ptr byte](cast[uint](s) + uint(a.len))
  BufReader(a: s, b: e)

proc newVarDef(name: NimNode, value: NimNode): NimNode =
  newTree(nnkVarSection, newIdentDefs(name, newEmptyNode(), value))

macro genDispatcherAux(name, objType, deserilizerType, serializerType: untyped, vtType: typed): untyped =
  let iObj = ident"obj"
  let iCmd = ident"cmd"
  let iSerializer = ident"serializer"
  let iDeserializer = ident"deserializer"
  let caseStmt = newTree(nnkCaseStmt, iCmd)

  var i = 0
  for n, t in interfaceProcs(vtType):

    # echo "NAME ", n, ": ", repr(t)
    let branchBody = newNimNode(nnkStmtList)
    let theCall = newCall(n, iObj)
    var j = 0
    for a in 1 ..< t[0].len:
      let par = t[0][a]
      for b in 0 .. par.len - 3:
        if j != 0:
          let iArg = ident("arg" & $j)
          theCall.add(iArg)
          branchBody.add(newVarDef(iArg, newCall("read", iDeserializer, newCall("type", par[^2]))))
        inc j
    branchBody.add(newCall("write", iSerializer, theCall))

    let ofBranch = newTree(nnkOfBranch, newLit(i + 3), branchBody)
    caseStmt.add(ofBranch)
    inc i

  caseStmt.add(newTree(nnkElse, newTree(nnkDiscardStmt, newEmptyNode())))

  result = quote do:
    proc`name`(`iObj`: `objType`, `iDeserializer`: ptr `deserilizerType`, `iSerializer`: ptr `serializerType`) =
      let `iCmd` = read(`iDeserializer`, uint16)
      try:
        `caseStmt`
      except Exception:
        write(`iSerializer`, uint16(1))
    `name`

  echo "dispatcher: ", treeRepr(result)

template genDispatcher(name, objType, deserilizerType, serializerType: untyped): untyped =
  genDispatcherAux(name, objType, deserilizerType, serializerType, objType.VTable)

proc newRpcConnection[T: Interface](rootObj: T): RpcConnection =
  let c = RpcConnection()

  # let d = genDispatcher(dispatch, T, BufReader, BufWriter)

  c.handler = proc(d: ptr BufReader, s: ptr BufWriter) {.async.} =
    genDispatcher(dispatch, T, BufReader, BufWriter)(rootObj, d, s)

  result = c

  # c.handler = proc(msg: seq[byte]): Future[void] =
  #   var reader = initBufReader(msg)
  #   let cmd = reader.read(uint16)
  #   case cmd
  #   of 0:
  #     discard
  #   of 1:
  #     discard
  #   of 2:
  #     var arg0 = read(reader, int)
  #     var arg1 = read(reader, int)
  #     var arg2 = read(reader, int)
  #     rootObj.say(arg0, arg1, arg2)


  #   if cmd > 1 and cmd < :
  #     discard # close
  #   elif cmd 

  # result = c

proc newRpcServer*(host: TransportAddress, rootObj: Interface): RpcServer =
  var r = RpcServerImpl[Interface](obj: rootObj)

  proc streamCallback(server: StreamServer, client: StreamTransport) {.async, gcsafe.} =
    let c = newRpcConnection(rootObj)
    let reader = newAsyncStreamReader(client)
    let writer = newAsyncStreamWriter(client)
    var buf: seq[byte]
    var bufWriter: BufWriter

    while true:
      var sz: uint16
      await reader.readExactly(addr sz, sizeof(sz))
      buf.setLen(sz)
      echo "msg len: ", sz
      await reader.readExactly(addr buf[0], sz.int)
      var bufReader = initBufReader(buf)
      bufWriter.data.setLen(sizeof(sz))
      await c.handler(addr bufReader, addr bufWriter)
      cast[ptr uint16](addr bufWriter.data[0])[] = bufWriter.data.len.uint16
      await writer.write(bufWriter.data)



    # let c = Connection()
    # c.reader = newAsyncStreamReader(client)
    # c.writer = newAsyncStreamWriter(client)

    echo "Connection received"
    echo await client.readLine()

  r.streamServer = createStreamServer(host, streamCallback)
  r.streamServer.start()
  r

proc newRpcClient*(host: TransportAddress, T: typedesc[Interface]): T =
  let tr = waitFor connect(host)
  echo "client connected"
  echo waitFor tr.write("Hello\r\n")
  

iface Animal:
  proc say(a, b: int, c: int): Future[void]
  proc go(): int

# genDispatcher(myDispatch, Animal, BufReader, BufWriter)


type Dog = ref object
  a: int

proc say(d: Dog, a, b, c: int): Future[void] =
  echo "Dog barks!: ", a, b, c, d.a

proc go(d: Dog): int =
  echo "Dog walks"
  return 5

let s = newRpcServer(commonAddress, Dog(a: 2).toAnimal)
let cl = newRpcClient(commonAddress, Animal)

proc test() {.async.} =
  echo cl.go()

waitFor test()

runForever()

# # proc say(this: Animal) {.inline.} =
# #   this.vTable.say(this.obj)

# echo "sizeof: ", sizeof(Animal.VTable)

# type Dog = ref object
#   a: int

# type Cat = ref object
#   a: int

# proc say(d: Dog, a, b, c: int) =
#   echo "Dog barks!: ", a, b, c, d.a

# proc say(d: Cat, a: int, b, c: int) =
#   echo "Cat meows! ", a, b, c, d.a

# proc go(d: Dog): int =
#   echo "Dog walks"
#   return 5

# proc go(d: Cat): int =
#   echo "Cat walks"

# proc foo(a: Animal) =
#   a.say(5, 6, 7)
#   echo a.go()

# proc test() =
#   foo(Dog(a: 1).toAnimal)
#   foo(Cat(a: 2).toAnimal)


# static:
#   test()

# test()

# let d = Dog()
# let a = toAnimal(d)
# a.say()
