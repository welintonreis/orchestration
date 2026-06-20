# Decodes a raw byte stream of WebSocket frames into application payloads, so the
# ttyd proxy can log what actually crosses the wire (debug only — see
# ContainersController#ttyd_ws). Handles client frames (masked) and server frames
# (unmasked) transparently by reading the MASK bit per RFC 6455, and buffers
# across chunk boundaries (one TCP read may hold a partial frame, or several).
#
# Not on the hot path unless TTYD_DEBUG_LOG / ?debug=1 is set — the normal proxy
# uses IO.copy_stream and never instantiates this.
class TtydWsDecoder
  def initialize
    @buf = (+"").b
  end

  # Append a chunk; yield [opcode, payload] for every complete data frame
  # (text 0x1 / binary 0x2) now available. Control frames are skipped.
  def feed(chunk)
    @buf << chunk.b
    while (frame = next_frame)
      opcode, payload = frame
      yield opcode, payload if opcode == 0x1 || opcode == 0x2
    end
  end

  private

  # Parse one frame off the front of @buf, or return nil if incomplete.
  def next_frame
    return nil if @buf.bytesize < 2
    b0     = @buf.getbyte(0)
    b1     = @buf.getbyte(1)
    opcode = b0 & 0x0f
    masked = (b1 & 0x80) != 0
    len    = b1 & 0x7f
    off    = 2

    if len == 126
      return nil if @buf.bytesize < off + 2
      len = @buf.byteslice(off, 2).unpack1("n"); off += 2
    elsif len == 127
      return nil if @buf.bytesize < off + 8
      len = @buf.byteslice(off, 8).unpack1("Q>"); off += 8
    end

    if masked
      return nil if @buf.bytesize < off + 4
      key = @buf.byteslice(off, 4).bytes; off += 4
    end

    return nil if @buf.bytesize < off + len
    payload = @buf.byteslice(off, len)
    payload = payload.bytes.each_with_index.map { |c, i| c ^ key[i % 4] }.pack("C*") if masked

    @buf = @buf.byteslice(off + len..) || (+"").b
    [opcode, payload]
  end
end
