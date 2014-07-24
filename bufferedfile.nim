const
  bufferSize* = 8192 ## size of a buffered file's buffer

type
  BufferedFile* = object
    file*: TFile
    buffer*: array[0..bufferSize, char] # TODO: Make this noinit
    curPos*: int ## current index in buffer
    bufLen*: int ## current length of buffer

# TODO: What do we do with the C internal bufSize, always set to 0?
proc open*(bf: var BufferedFile; filename: string; mode: TFileMode = fmRead;
           bufSize: int = - 1): bool {.tags: [], gcsafe.} =
  result = bf.file.open(filename, mode, bufSize)
  bf.curPos = 0
  bf.bufLen = 0

proc open*(bf: var BufferedFile; filehandle: TFileHandle;
          mode: TFileMode = fmRead): bool {.tags: [], gcsafe.} =
  result = bf.file.open(filehandle, mode)
  bf.curPos = 0
  bf.bufLen = 0

proc open*(filename: string, mode: TFileMode = fmRead, bufSize: int = -1):
           BufferedFile {.tags: [], gcsafe.} =
  result.file = system.open(filename, mode, bufSize)

proc buffered*(file: TFile): BufferedFile {.tags: [], gcsafe.} =
  result.file = file

proc refillBuffer(bf: var BufferedFile) =
  bf.curPos = 0
  bf.bufLen = readChars(bf.file, bf.buffer, 0, bufferSize)

proc readChar*(bf: var BufferedFile): char =
  if bf.curPos >= bf.bufLen:
    bf.refillBuffer

  result = bf.buffer[bf.curPos]
  inc bf.curPos

proc raiseEIO(msg: string) {.noinline, noreturn.} =
  raise newException(EIO, msg)

template addUntil(i): stmt {.immediate.} =
  ## Helper for readLine; Adds part of a char-array to a string efficiently
  let nll = ll + i - bf.curPos
  line.string.setLen(nll)
  copyMem(addr line.string[ll], addr bf.buffer[bf.curPos], i - bf.curPos)
  ll = nll

proc readLine*(bf: var BufferedFile, line: var TaintedString): bool
               {.tags: [FReadIO], gcsafe, raises: [].} =
  var
    i = bf.curPos
    ll = 0
  line.string.setLen(ll)

  if bf.bufLen == 0:
    bf.refillBuffer
    if bf.bufLen == 0:
      return false

  while true:
    for i in bf.curPos .. <bf.bufLen:
      if bf.buffer[i] == '\l':
        addUntil(i)
        bf.curPos = i + 1
        return true
      if bf.buffer[i] == '\r':
        addUntil(i)
        if i+1 < bf.bufLen and bf.buffer[i+1] == '\l':
          bf.curPos = i + 2
        else:
          bf.curPos = i + 1
        return true
    if bf.bufLen > 0:
      addUntil(bf.bufLen)
    bf.refillBuffer
    if bf.bufLen == 0:
      return ll > 0

proc readLine*(bf: var BufferedFile): TaintedString {.tags: [FReadIO], gcsafe.} =
  result = TaintedString(newStringOfCap(80))
  if not readLine(bf, result): raiseEIO("EOF reached")

iterator items*(bf: var BufferedFile): string =
  var line = TaintedString(newStringOfCap(80))
  while bf.readLine(line):
    yield line

when isMainModule:
  var count = 0
  var sum = 0

  var line = ""
  var bstdin = stdin.buffered
  #while stdin.readLine(line): # 4.31 s
  #for line in bstdin: # 1.72 s (because the string is copied every time, TODO: how to prevent?)
  while bstdin.readLine(line): # 0.74 s
    count += 1
    sum += line.len

  echo "Average line length: ",
    if count > 0: sum / count else: 0
