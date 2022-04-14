package chip8

@(private)
VERTEX_SOURCE ::`
    #version 330 core
    layout (location = 0) in vec2 inPosition;

    uniform mat4 uProjection;

    void main()
    {
        gl_Position = uProjection * vec4(inPosition, 0.0, 1.0);
    }`

@(private)
FRAGMENT_SOURCE ::`
    #version 330 core
    out vec4 FragColor;

    void main()
    {
        FragColor = vec4(1.0, 1.0, 1.0, 1.0);
    }`