# A zip file built byte by byte (stored entries, no compression), so a test
# can name an entry whatever it likes: a `../` component, a non-ASCII file
# name, a name the server would never send. No external `zip` binary is
# involved, which keeps the tests the same on every CI runner. `entries`
# is a named list, entry name -> raw content; names are written as UTF-8
# with the general-purpose flag bit 11 set, as Info-ZIP does.
stored_zip <- function(path, entries) {
  locals <- raw()
  central <- raw()
  offset <- 0L
  for (name in names(entries)) {
    data <- entries[[name]]
    nm <- charToRaw(enc2utf8(name))
    crc <- crc32(data)
    fixed <- c(
      zip_le16(20L), zip_le16(0x0800L), zip_le16(0L), zip_le16(0L), zip_le16(0L),
      zip_le32(crc), zip_le32(length(data)), zip_le32(length(data)), zip_le16(length(nm))
    )
    header <- c(as.raw(c(0x50, 0x4b, 0x03, 0x04)), fixed, zip_le16(0L), nm)
    central <- c(
      central,
      as.raw(c(0x50, 0x4b, 0x01, 0x02)), zip_le16(20L), fixed,
      zip_le16(0L), zip_le16(0L), zip_le16(0L), zip_le16(0L), zip_le32(0), zip_le32(offset), nm
    )
    locals <- c(locals, header, data)
    offset <- offset + length(header) + length(data)
  }
  n <- length(entries)
  eocd <- c(
    as.raw(c(0x50, 0x4b, 0x05, 0x06)), zip_le16(0L), zip_le16(0L), zip_le16(n), zip_le16(n),
    zip_le32(length(central)), zip_le32(length(locals)), zip_le16(0L)
  )
  writeBin(c(locals, central, eocd), path)
  invisible(path)
}

zip_le16 <- function(x) {
  as.raw(c(x %% 256, (x %/% 256) %% 256))
}

zip_le32 <- function(x) {
  # `x` may exceed the integer range (a CRC as an unsigned value)
  as.raw(c(x %% 256, (x %/% 256) %% 256, (x %/% 65536) %% 256, (x %/% 16777216) %% 256))
}

# CRC-32 (IEEE 802.3), the checksum zip stores per entry; R's unzip
# verifies it. Signed 32-bit arithmetic throughout (the polynomial
# 0xEDB88320 is -306674912 as a signed integer; bitwShiftR() shifts as
# unsigned), converted to the unsigned value at the end.
crc32_table <- local({
  table <- integer(256)
  for (n in 0:255) {
    c <- n
    for (k in 1:8) {
      c <- if (bitwAnd(c, 1L) == 1L) bitwXor(bitwShiftR(c, 1L), -306674912L) else bitwShiftR(c, 1L)
    }
    table[n + 1] <- c
  }
  table
})

crc32 <- function(bytes) {
  crc <- -1L
  for (b in as.integer(bytes)) {
    crc <- bitwXor(bitwShiftR(crc, 8L), crc32_table[bitwAnd(bitwXor(crc, b), 255L) + 1L])
  }
  crc <- bitwNot(crc)
  if (crc < 0) crc + 4294967296 else crc
}

# Serve a zip built at test time, the way mock_zip() serves a fixture.
mock_zip_file <- function(path, status = 200) {
  httr2::response(
    status_code = status,
    headers = list(`content-type` = "application/zip"),
    body = readBin(path, "raw", n = file.size(path))
  )
}
