package chip8

import "core:fmt"
import "core:math/linalg"
import "core:math/rand"
import "core:os"
import "shared:soloud"
import "vendor:glfw"
import gl "vendor:opengl"
import sa "core:container/small_array"

Vec2   :: linalg.Vector2f32
Mat4   :: linalg.Matrix4f32
Vertex :: Vec2

BUFFER_SIZE   :: 2049 * 6
WIDTH         :: 64
HEIGHT        :: 32
SCREEN_WIDTH  :: 1024
SCREEN_HEIGHT :: 512
SPEED         :: 10

///////////////////////////////////////////////////////////
// Gfx
///////////////////////////////////////////////////////////

Gfx :: struct {
    buffer: struct {
        vao: u32,
        vbo: u32,
    },

    data:       [BUFFER_SIZE]Vertex,
    projection: Mat4,
    shader:     u32,
    uniforms:   gl.Uniforms,
}

@(private="file")
_gfx: Gfx

@(private="file")
_init_gfx :: proc() {
    using _gfx

    projection = linalg.matrix_ortho3d(f32(0.0), WIDTH, HEIGHT, 0.0, -1.0, 1.0)

    gl.GenBuffers(1, &buffer.vbo)
    gl.GenVertexArrays(1, &buffer.vao)

    gl.BindVertexArray(buffer.vao)

    gl.BindBuffer(gl.ARRAY_BUFFER, buffer.vbo)
    gl.BufferData(gl.ARRAY_BUFFER, BUFFER_SIZE * size_of(Vertex), nil, gl.DYNAMIC_DRAW)

    gl.EnableVertexAttribArray(0)
    gl.VertexAttribPointer(0, 2, gl.FLOAT, gl.FALSE, i32(2 * size_of(f32)), cast(uintptr)(0))

    ok: bool
    shader, ok = gl.load_shaders_source(VERTEX_SOURCE, FRAGMENT_SOURCE)
    if ok {
        uniforms = gl.get_uniforms_from_program(shader)
    }

    gl.Viewport(0, 0, SCREEN_WIDTH, SCREEN_HEIGHT)
}

@(private="file")
_destroy_gfx :: proc() {
    using _gfx

    gl.DeleteBuffers(1, &buffer.vbo)
    gl.DeleteVertexArrays(1, &buffer.vao)
    gl.DeleteShader(shader)
    gl.destroy_uniforms(uniforms)
}


draw :: proc() {
    using _gfx

    i := 0
    for y in 0..<HEIGHT {
        for x in 0..<WIDTH {
            if _cpu.buffer[x + (y * WIDTH)] != 0 {
                data[i * 6 + 0] = {f32(x) + 1, f32(y) + 1}
                data[i * 6 + 1] = {f32(x) + 1, f32(y)}
                data[i * 6 + 2] = {f32(x),     f32(y)}
                data[i * 6 + 3] = {f32(x),     f32(y)}
                data[i * 6 + 4] = {f32(x),     f32(y) + 1}
                data[i * 6 + 5] = {f32(x) + 1, f32(y) + 1}
                i += 1
            }
        }
    }

    gl.ClearColor(0.0, 0.0, 0.0, 1.0)
    gl.Clear(gl.COLOR_BUFFER_BIT)

    gl.UseProgram(shader)
    gl.UniformMatrix4fv(uniforms["uProjection"].location, 1, false, &projection[0][0])

    gl.BindVertexArray(buffer.vao)
    gl.BindBuffer(gl.ARRAY_BUFFER, buffer.vbo)
    gl.BufferSubData(gl.ARRAY_BUFFER, 0, i * size_of(Vertex) * 6, &data[0])
    gl.DrawArrays(gl.TRIANGLES, 0, i32(i) * 6)
    gl.BindVertexArray(0)
    gl.UseProgram(0)
}

///////////////////////////////////////////////////////////
// Audio
///////////////////////////////////////////////////////////

Audio :: struct {
    core:  soloud.Soloud,
    sound: soloud.Wav,
}

@(private="file")
_audio: Audio

@(private="file")
_init_audio :: proc() {
    using _audio

    core = soloud.create()
    soloud.init(core)

    sound = soloud.wav_create()
    soloud.wav_load(sound, "sound.wav")
}

@(private="file")
_destroy_audio :: proc() {
    using _audio

    soloud.stop_all(core)
    soloud.wav_destroy(sound)
    soloud.deinit(core)
    soloud.destroy(core)
}

///////////////////////////////////////////////////////////
// Input
///////////////////////////////////////////////////////////

@(private="file")
_keymap := map[int]int{
    0x1 = 49, // 1 -> 1
    0x2 = 50, // 2 -> 2
    0x3 = 51, // 3 -> 3
    0xC = 52, // C -> 4
    0x4 = 81, // 4 -> Q
    0x5 = 87, // 5 -> W
    0x6 = 69, // 6 -> E
    0xD = 82, // D -> R
    0x7 = 65, // 7 -> A
    0x8 = 83, // 8 -> S
    0x9 = 68, // 9 -> D
    0xE = 70, // E -> F
    0xA = 90, // A -> Z
    0x0 = 88, // 0 -> X
    0xB = 67, // B -> C
    0xF = 86, // F -> V
}

Key_State :: struct {
    exists: bool,
    value:  u8,
}

Input :: struct {
    keys:  sa.Small_Array(384, int),
    state: [384]Key_State,
}

@(private="file")
_input: Input

@(private="file")
_is_key_down :: proc(hex_key: int) -> bool {
    using _input

    key := _keymap[hex_key]
    if !state[key].exists {
        sa.push(&keys, key)
        state[key].exists = true
    }
    return state[key].value == 1
}

update_input :: proc(window: glfw.WindowHandle) {
    using _input

    for i in 0..<sa.len(keys) {
        key := sa.get(keys, i)
        state[key].value = u8(glfw.GetKey(window, i32(key)))
    }
}

///////////////////////////////////////////////////////////
// CPU
///////////////////////////////////////////////////////////

Chip8 :: struct {
    opcode:      u16,
    memory:      [4096]byte,
    v:           [16]byte,
    i:           u16,
    pc:          u16,
    delay_timer: byte,
    sound_timer: byte,
    buffer:      [2048]byte,
    stack:       [16]u16,
    sp:          u16,
}

@(private="file")
_cpu: Chip8

@(private="file")
_fontset := [80]byte {
    0xF0, 0x90, 0x90, 0x90, 0xF0, // 0
    0x20, 0x60, 0x20, 0x20, 0x70, // 1
    0xF0, 0x10, 0xF0, 0x80, 0xF0, // 2
    0xF0, 0x10, 0xF0, 0x10, 0xF0, // 3
    0x90, 0x90, 0xF0, 0x10, 0x10, // 4
    0xF0, 0x80, 0xF0, 0x10, 0xF0, // 5
    0xF0, 0x80, 0xF0, 0x90, 0xF0, // 6
    0xF0, 0x10, 0x20, 0x40, 0x40, // 7
    0xF0, 0x90, 0xF0, 0x90, 0xF0, // 8
    0xF0, 0x90, 0xF0, 0x10, 0xF0, // 9
    0xF0, 0x90, 0xF0, 0x90, 0x90, // A
    0xE0, 0x90, 0xE0, 0x90, 0xE0, // B
    0xF0, 0x80, 0x80, 0x80, 0xF0, // C
    0xE0, 0x90, 0x90, 0x90, 0xE0, // D
    0xF0, 0x80, 0xF0, 0x80, 0xF0, // E
    0xF0, 0x80, 0xF0, 0x80, 0x80, // F
}

@(private="file")
_init_cpu :: proc() {
    using _cpu

    i      = 0
    opcode = 0
    pc     = 0x200
    sp     = 0

    buffer = {}
    stack  = {}
    v      = {}
    memory = {}

    delay_timer = 0
    sound_timer = 0

    // lataa fontset 0 - 80 (0x50)
    for i in 0..<80 {
        memory[i] = _fontset[i]
    }
}

init :: proc() {
    _init_cpu()
    _init_gfx()
    _init_audio()
}

deinit :: proc() {
    delete(_keymap)
    _destroy_gfx()
    _destroy_audio()
}

load :: proc(name: string) {
    if os.is_file(name) {
        buffer, ok := os.read_entire_file(name)
        if ok {
            if len(buffer) < 4096 {
                for i in 0..<len(buffer) {
                    _cpu.memory[0x200 + i] = buffer[i]
                }
            } else {
                fmt.println("Rom is too big.")
            }
            delete(buffer)
        }
    }
}

emulate :: proc() {
    for i in 0..<SPEED {
        _execute_opcode()
    }
    _update_timers()
}

@(private="file")
_execute_opcode :: proc() {
    using _cpu

    // Hae opcode
    opcode = u16(memory[pc]) << 8 | u16(memory[pc + 1])

    // 0x0XY0
    x := (opcode & 0x0F00) >> 8
    y := (opcode & 0x00F0) >> 4

    // decoodaa opcode
    switch (opcode & 0xF000) {

        case 0x0000:
            switch (opcode & 0x000F) {
                // Clears the screen.
                case 0x0000:
                    buffer = {}
                    pc += 2

                // Returns from a subroutine.
                case 0x000E:
                    sp -= 1
                    pc = stack[sp]
                    pc += 2

                case:
                    fmt.printf("Unknown opcode [0x0000]: 0x%X\n", opcode)
            }

        // Jumps to address NNN.
        case 0x1000:
            pc = opcode & 0x0FFF

        // Calls subroutine at NNN.
        case 0x2000:
            stack[sp] = pc
            sp += 1
            pc = opcode & 0x0FFF

        // Skips the next instruction if VX equals NN.
        case 0x3000:
            if v[x] == byte(opcode & 0x00FF) {
                pc += 4
            } else {
                pc += 2
            }

        // Skips the next instruction if VX does not equal NN.
        case 0x4000:
            if v[x] != byte(opcode & 0x00FF) {
                pc += 4
            } else {
                pc += 2
            }

        // Skips the next instruction if VX equals VY.
        case 0x5000:
            if v[x] == v[y] {
                pc += 4
            } else {
                pc += 2
            }

        // Sets VX to NN.
        case 0x6000:
            v[x] = byte(opcode & 0x00FF)
            pc += 2

        // Adds NN to VX. (Carry flag is not changed);
        case 0x7000:
            v[x] += byte(opcode & 0x00FF)
            pc += 2

        case 0x8000:
            switch (opcode & 0x000F) {
                // Sets VX to the value of VY.
                case 0x0000:
                    v[x] = v[y]
                    pc += 2

                // Sets VX to VX or VY. (Bitwise OR operation);
                case 0x0001:
                    v[x] |= v[y]
                    pc += 2

                // Sets VX to VX and VY. (Bitwise AND operation);
                case 0x0002:
                    v[x] &= v[y]
                    pc += 2

                // Sets VX to VX xor VY.
                case 0x0003:
                    v[x] ~= v[y]
                    pc += 2

                // Adds VY to VX. VF is set to 1 when there's a carry, and to 0 when there is not.
                case 0x0004:
                    if v[y] > (0xFF - v[x]) {
                        v[0xF] = 1
                    } else {
                        v[0xF] = 0
                    }
                    v[x] += v[y]
                    pc += 2

                // VY is subtracted from VX. VF is set to 0 when there's a borrow, and 1 when there is not.
                case 0x0005:
                    if v[y] > v[x] {
                        v[0xF] = 0 // borrow
                    } else {
                        v[0xF] = 1
                    }
                    v[x] -= v[y]
                    pc += 2

                // Stores the least significant bit of VX in VF and then shifts VX to the right by 1.
                case 0x0006:
                    v[0xF] = v[x] & 0x1
                    v[x] >>= 1
                    pc += 2

                // Sets VX to VY minus VX. VF is set to 0 when there's a borrow, and 1 when there is not.
                case 0x0007:
                    if (v[x] > v[y]) {
                        v[0xF] = 0
                    } else {
                        v[0xF] = 1
                    }
                    v[x] = v[y] - v[x]
                    pc += 2

                // Stores the most significant bit of VX in VF and then shifts VX to the left by 1.
                case 0x000E:
                    v[0xF] = v[x] >> 7
                    v[x] <<= 1
                    pc += 2

                case:
                    fmt.printf("Unknown opcode [0x8000]: 0x%X\n", opcode)
            }

        // Skips the next instruction if VX does not equal VY.
        case 0x9000:
            if v[x] != v[y] {
                pc += 4
            } else {
                pc += 2
            }

        // Sets I to the address NNN.
        case 0xA000:
            i = opcode & 0x0FFF
            pc += 2

        // Jumps to the address NNN plus V0.
        case 0xB000:
            pc = (opcode & 0x0FFF) + u16(v[0])

        // Sets VX to the result of a bitwise and operation on a random number (Typically: 0 to 255) and NN.
        case 0xC000:
            v[x] = u8(rand.int_max(255) % 0xFF) & u8(opcode & 0x00FF)
            pc += 2

        // Draws a sprite at coordinate (VX, VY) that has a width of 8 pixels and a height of N pixels. Each row of 8 pixels is read as bit-coded starting from memory location I;
        // I value does not change after the execution of this instruction. As described above, VF is set to 1 if any screen pixels are flipped from set to unset when the sprite is drawn,
        // and to 0 if that does not happen
        case 0xD000:
            vx: u16 = u16(v[x])
            vy: u16 = u16(v[y])
            height: u16 = (opcode & 0x000F)

            v[0xF] = 0
            for yline in 0..<height {

                line := u16(memory[i + yline])
                for xline in 0..<8 {
                    if (line & 0x80) > 0 { // tai (line & (0x80 >> u16(xline)) != 0)
                        xp := (vx + u16(xline)) % WIDTH
                        yp := (vy + u16(yline)) % HEIGHT
                        index := xp + yp * WIDTH
                        if buffer[index] == 1 {
                            v[0xF] = 1
                        }
                        buffer[index] ~= 1
                    }
                    line <<= 1 // siirtyy seuraavan pikseliin
                }
            }
            pc += 2

        case 0xE000:
            switch (opcode & 0x00FF) {
                // Skips the next instruction if the key stored in VX is pressed.
                case 0x009E:
                    if _is_key_down(int(v[x])) {
                        pc += 4
                    } else {
                        pc += 2
                    }

                // Skips the next instruction if the key stored in VX is not pressed.
                case 0x00A1:
                    if !_is_key_down(int(v[x])) {
                        pc += 4
                    } else {
                        pc += 2
                    }

                case:
                    fmt.printf("Unknown opcode [0xE000]: 0x%X\n", opcode)
            }

        case 0xF000:
            switch (opcode & 0x00FF) {
                // Sets VX to the value of the delay timer.
                case 0x0007:
                    v[x] = delay_timer
                    pc += 2

                // A key press is awaited, and then stored in VX. (Blocking Operation. All instruction halted until next key event);
                case 0x000A:
                    key_pressed := false
                    for j in 0..<16 {
                        if _is_key_down(j) {
                            v[x] = u8(j)
                            key_pressed = true
                        }
                    }
                    if key_pressed {
                        pc += 2
                    }

                // Sets the delay timer to VX.
                case 0x0015:
                    delay_timer = v[x]
                    pc += 2

                // Sets the sound timer to VX.
                case 0x0018:
                    sound_timer = v[x]
                    pc += 2

                // Adds VX to I. VF is not affected
                case 0x001E:
                    if (i + u16(v[x]) > 0xFFF) {   // VF is set to 1 when range overflow (I+VX>0xFFF), and 0 when there isn't.
                        v[0xF] = 1
                    } else {
                        v[0xF] = 0
                    }
                    i += u16(v[x])
                    pc += 2

                // Sets I to the location of the sprite for the character in VX. Characters 0-F (in hexadecimal) are represented by a 4x5 font.
                case 0x0029:
                    i = u16(v[x]) * 5 // 5 * koska fontti 5 pikselia levee
                    pc += 2

                // Stores the binary-coded decimal representation of VX, with the most significant of three digits at the address in I, the middle digit at I plus 1,
                // and the least significant digit at I plus 2. (In other words, take the decimal representation of VX, place the hundreds digit in
                // memory at location in I, the tens digit at location I+1, and the ones digit at location I+2.);
                case 0x0033:
                    memory[i + 0] = v[x] / 100
                    memory[i + 1] = (v[x] / 10) % 10
                    memory[i + 2] = (v[x] % 100) % 10
                    pc += 2

                // Stores from V0 to VX (including VX) in memory, starting at address I. The offset from I is increased by 1 for each value written, but I itself is left unmodified.
                case 0x0055:
                    for j in 0..=x {
                        memory[i + j] = v[j]
                    }
                    i += x + 1
                    pc += 2

                // Fills from V0 to VX (including VX) with values from memory, starting at address I. The offset from I is increased by 1 for each value written, but I itself is left unmodified.
                case 0x0065:
                    for j in 0..=x {
                        v[j] = memory[i + j]
                    }
                    i += x + 1
                    pc += 2

                case:
                    fmt.printf("Unknown opcode [0xF000]: 0x%X\n", opcode)
            }


        case:
            fmt.printf("Unknown opcode: 0x%X\n", opcode)
    }
}

@(private="file")
_update_timers :: proc() {
    using _cpu

    if delay_timer > 0 {
        delay_timer -= 1
    }

    if sound_timer > 0 {
        if sound_timer == 1 {
            soloud.play(_audio.core, _audio.sound)
        }
        sound_timer -= 1
    }
}