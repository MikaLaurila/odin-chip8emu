package main

import "chip8"
import "core:fmt"
import "core:os"
import "core:time"
import "vendor:glfw"
import gl "vendor:opengl"

main :: proc() {
    if len(os.args) < 2 {
        fmt.println("Error: No command-line arguments specified.")
        return
    }

    window: glfw.WindowHandle

    if glfw.Init() != 1 {
        fmt.println("Error: GLFW Init failed.")
        return
    }

    glfw.WindowHint(glfw.RESIZABLE, 0)
    window = glfw.CreateWindow(chip8.SCREEN_WIDTH, chip8.SCREEN_HEIGHT, "Odin Chip-8 Emulator", nil, nil)
    if window == nil {
        glfw.Terminate()
        return
    }

    glfw.SwapInterval(1)
    glfw.MakeContextCurrent(window)
    gl.load_up_to(3, 3, glfw.gl_set_proc_address)

    chip8.init()
    chip8.load(os.args[1])

    delta_t := 0.0
    next_t  := 0.0
    now_t   := 0.0
    start_t := 0.0

    for glfw.WindowShouldClose(window) == glfw.FALSE {
        next_t += (1.0 / 60.0)
        now_t = glfw.GetTime()
        delta_t = now_t - start_t
        start_t = now_t

        glfw.PollEvents()

        chip8.update_input(window)
        chip8.emulate()
        chip8.draw()

        glfw.SwapBuffers(window)

        now_t = glfw.GetTime()
        if next_t <= now_t {
            next_t = now_t
        } else {
            t := (next_t - now_t) * 1000000000
            time.sleep(time.Duration(t))
        }
    }

    chip8.deinit()
    glfw.Terminate()
}