# For HTML5-capable browsers, file uploads happen through a series of requests.
#
# 1. Client tells server that one or more files are about to be uploaded; the
#    server responds with a "job ID" that the client should use for the rest of
#    the upload.
#
# 2. For each file (sequentially):
#    a. Client tells server the name, size, and type of the file.
#    b. Client sends server a small-ish blob of data.
#    c. Repeat 2b until the entire file has been uploaded.
#    d. Client tells server that the current file is done.
#
# 3. Repeat 2 until all files have been uploaded.
#
# 4. Client tells server that all files have been uploaded, along with the
#    input ID that this data should be associated with.
#
# Unfortunately this approach will not work for browsers that don't support
# HTML5 File API, but the fallback approach we would like to use (multipart
# form upload, i.e. traditional HTTP POST-based file upload) doesn't work with
# the websockets package's HTTP server at the moment.

FileUploadOperation <- R6Class(
  'FileUploadOperation',
  portable = FALSE,
  class = FALSE,
  public = list(
    .parent = NULL,
    .id = character(0),
    .files = data.frame(),
    .dir = character(0),
    .currentFileInfo = list(),
    .currentFileData = NULL,
    .pendingFileInfos = list(),

    initialize = function(parent, id, dir, fileInfos) {
      .parent <<- parent
      .id <<- id
      .files <<- data.frame(name=character(),
                            size=numeric(),
                            type=character(),
                            datapath=character(),
                            stringsAsFactors=FALSE)
      .dir <<- dir
      .pendingFileInfos <<- fileInfos
    },
    fileBegin = function() {
      if (length(.pendingFileInfos) < 1)
        stop("fileBegin called too many times")

      file <- .pendingFileInfos[[1]]
      .currentFileInfo <<- file
      .pendingFileInfos <<- tail(.pendingFileInfos, -1)

      filename <- file.path(.dir, as.character(length(.files$name)))
      row <- data.frame(name=file$name, size=file$size, type=file$type,
                        datapath=filename, stringsAsFactors=FALSE)

      if (length(.files$name) == 0)
        .files <<- row
      else
        .files <<- rbind(.files, row)

      .currentFileData <<- file(filename, open='wb')
    },
    fileChunk = function(rawdata) {
      writeBin(rawdata, .currentFileData)
    },
    fileEnd = function() {
      close(.currentFileData)
    },
    finish = function() {
      if (length(.pendingFileInfos) > 0)
        stop("File upload job was stopped prematurely")
      .parent$onJobFinished(.id)
      return(.files)
    }
  )
)

#' @include map.R
FileUploadContext <- R6Class(
  'FileUploadContext',
  portable = FALSE,
  class = FALSE,
  public = list(
    .basedir = character(0),
    .operations = 'Map',

    initialize = function(dir=tempdir()) {
      .basedir <<- dir
      .operations <<- Map$new()
    },
    createUploadOperation = function(fileInfos) {
      while (TRUE) {
        id <- paste(as.raw(p_runif(12, min=0, max=0xFF)), collapse='')
        dir <- file.path(.basedir, id)
        if (!dir.create(dir))
          next

        op <- FileUploadOperation$new(self, id, dir, fileInfos)
        .operations$set(id, op)
        return(id)
      }
    },
    getUploadOperation = function(jobId) {
      .operations$get(jobId)
    },
    onJobFinished = function(jobId) {
      .operations$remove(jobId)
    }
  )
)
