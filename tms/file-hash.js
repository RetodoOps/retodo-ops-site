(function (root) {
  'use strict';

  const K = new Uint32Array([
    0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
    0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
    0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
    0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
    0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
    0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
    0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
    0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2,
  ]);

  const rotateRight = (value, bits) => (value >>> bits) | (value << (32 - bits));

  class Sha256 {
    constructor() {
      this.state = new Uint32Array([
        0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,
        0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19,
      ]);
      this.buffer = new Uint8Array(64);
      this.bufferLength = 0;
      this.totalBytes = 0;
      this.finished = false;
    }

    update(input) {
      if (this.finished) throw new Error('SHA-256 digest is already finalized.');
      const bytes = input instanceof Uint8Array ? input : new Uint8Array(input);
      this.totalBytes += bytes.length;
      let offset = 0;
      while (offset < bytes.length) {
        const length = Math.min(64 - this.bufferLength, bytes.length - offset);
        this.buffer.set(bytes.subarray(offset, offset + length), this.bufferLength);
        this.bufferLength += length;
        offset += length;
        if (this.bufferLength === 64) {
          this.compress(this.buffer);
          this.bufferLength = 0;
        }
      }
      return this;
    }

    compress(block) {
      const words = new Uint32Array(64);
      for (let index = 0; index < 16; index += 1) {
        const offset = index * 4;
        words[index] = ((block[offset] << 24) | (block[offset + 1] << 16)
          | (block[offset + 2] << 8) | block[offset + 3]) >>> 0;
      }
      for (let index = 16; index < 64; index += 1) {
        const x = words[index - 15], y = words[index - 2];
        const s0 = rotateRight(x, 7) ^ rotateRight(x, 18) ^ (x >>> 3);
        const s1 = rotateRight(y, 17) ^ rotateRight(y, 19) ^ (y >>> 10);
        words[index] = (words[index - 16] + s0 + words[index - 7] + s1) >>> 0;
      }
      let [a,b,c,d,e,f,g,h] = this.state;
      for (let index = 0; index < 64; index += 1) {
        const s1 = rotateRight(e, 6) ^ rotateRight(e, 11) ^ rotateRight(e, 25);
        const choice = (e & f) ^ (~e & g);
        const first = (h + s1 + choice + K[index] + words[index]) >>> 0;
        const s0 = rotateRight(a, 2) ^ rotateRight(a, 13) ^ rotateRight(a, 22);
        const majority = (a & b) ^ (a & c) ^ (b & c);
        const second = (s0 + majority) >>> 0;
        h = g; g = f; f = e; e = (d + first) >>> 0;
        d = c; c = b; b = a; a = (first + second) >>> 0;
      }
      this.state[0] = (this.state[0] + a) >>> 0;
      this.state[1] = (this.state[1] + b) >>> 0;
      this.state[2] = (this.state[2] + c) >>> 0;
      this.state[3] = (this.state[3] + d) >>> 0;
      this.state[4] = (this.state[4] + e) >>> 0;
      this.state[5] = (this.state[5] + f) >>> 0;
      this.state[6] = (this.state[6] + g) >>> 0;
      this.state[7] = (this.state[7] + h) >>> 0;
    }

    hex() {
      if (!this.finished) {
        const length = this.bufferLength;
        this.buffer[length] = 0x80;
        this.buffer.fill(0, length + 1);
        if (length >= 56) {
          this.compress(this.buffer);
          this.buffer.fill(0);
        }
        const high = Math.floor(this.totalBytes / 0x20000000);
        const low = (this.totalBytes * 8) >>> 0;
        this.buffer[56] = high >>> 24;
        this.buffer[57] = high >>> 16;
        this.buffer[58] = high >>> 8;
        this.buffer[59] = high;
        this.buffer[60] = low >>> 24;
        this.buffer[61] = low >>> 16;
        this.buffer[62] = low >>> 8;
        this.buffer[63] = low;
        this.compress(this.buffer);
        this.finished = true;
      }
      return [...this.state].map(word => word.toString(16).padStart(8, '0')).join('');
    }
  }

  async function sha256Hex(blob, onProgress) {
    if (!blob || typeof blob.size !== 'number') throw new Error('A file is required.');
    const hasher = new Sha256();
    let processed = 0;
    if (typeof blob.stream === 'function') {
      const reader = blob.stream().getReader();
      while (true) {
        const {done, value} = await reader.read();
        if (done) break;
        hasher.update(value);
        processed += value.byteLength;
        onProgress?.(processed, blob.size);
      }
    } else {
      const chunkSize = 4 * 1024 * 1024;
      while (processed < blob.size) {
        const chunk = await blob.slice(processed, processed + chunkSize).arrayBuffer();
        hasher.update(new Uint8Array(chunk));
        processed += chunk.byteLength;
        onProgress?.(processed, blob.size);
      }
    }
    if (blob.size === 0) onProgress?.(0, 0);
    return hasher.hex();
  }

  root.TMS_FILE_HASH = Object.freeze({Sha256, sha256Hex});
})(globalThis);
