// 스텝모터 이벤트 룰렛 (5주차 1상 여자: A -> B -> /A -> /B)
//   home  : 원점 센서가 감지될 때까지 돌리고 그 자리를 0으로 잡음 (타이틀·리셋 때)
//   spin  : SPIN_REVS 바퀴 + 목표 칸까지 돌림. 마지막 SLOW_STEPS 스텝은 천천히 (룰렛 감속)
//   원판에는 원점에서 같은 방향으로 60°마다 이벤트 6개를 붙여요 (0 LAVA, 1 LOW-G, 2 GUST, 3 QUAKE, 4 FOG, 5 METEOR)
//   보드 스텝모터의 1바퀴 스텝 수를 STEPS_PER_REV 에 맞춰 주세요.
module stepper_ctrl #(
    parameter integer STEPS_PER_REV = 200,
    parameter integer FAST_MS    = 4,      // 빠를 때 스텝 간격 (ms)
    parameter integer SLOW_MS    = 12,     // 느릴 때 스텝 간격 (ms)
    parameter integer SLOW_STEPS = 30,
    parameter integer SPIN_REVS  = 1,
    parameter         HOME_LEVEL = 1'b1,   // 원점 센서가 감지됐을 때 값
    parameter         HOLD       = 1'b0    // 1이면 멈춘 뒤에도 코일 전류 유지
) (
    input  wire       clk,
    input  wire       rst,
    input  wire       tick_ms,
    input  wire       home,           // 1클럭 펄스
    input  wire       spin,           // 1클럭 펄스
    input  wire [2:0] target_sector,  // 0~5
    input  wire       sensor,         // 보드 Step Sensor
    output wire       busy,
    output reg        sector_tick,    // 칸 경계를 지날 때 1클럭 (딸깍 소리)
    output wire [3:0] coil            // {A, B, /A, /B}
);
    localparam [1:0] S_IDLE = 2'd0, S_HOME = 2'd1, S_SPIN = 2'd2;

    reg [1:0]  st;
    reg [9:0]  pos;          // 0 ~ STEPS_PER_REV-1
    reg [11:0] remain;       // 남은 스텝
    reg [4:0]  wait_ms;
    reg [1:0]  phase;
    reg [2:0]  sector_d;
    reg [1:0]  sens_s;       // 동기화

    wire [9:0]  target_pos = (target_sector * STEPS_PER_REV) / 6;
    wire [9:0]  delta      = (target_pos + STEPS_PER_REV - pos) % STEPS_PER_REV;
    wire [2:0]  sector     = (pos * 6) / STEPS_PER_REV;
    wire        at_home    = (sens_s[1] == HOME_LEVEL);
    wire [4:0]  interval   = ((st == S_SPIN) && (remain <= SLOW_STEPS)) ? SLOW_MS : FAST_MS;

    assign busy = (st != S_IDLE);
    assign coil = (busy || HOLD) ? (4'b1000 >> phase) : 4'b0000;

    always @(posedge clk) begin
        if (rst) begin
            st <= S_IDLE; pos <= 10'd0; remain <= 12'd0; wait_ms <= 5'd0; phase <= 2'd0;
            sector_d <= 3'd0; sens_s <= 2'b00; sector_tick <= 1'b0;
        end else begin
            sens_s      <= {sens_s[0], sensor};
            sector_d    <= sector;
            sector_tick <= (sector != sector_d);

            if (home) begin
                st <= S_HOME;
                remain <= 2 * STEPS_PER_REV;        // 센서를 못 찾으면 2바퀴 뒤 포기
                wait_ms <= 5'd0;
            end else if (spin) begin
                st <= S_SPIN;
                remain <= SPIN_REVS * STEPS_PER_REV + delta;
                wait_ms <= 5'd0;
            end else if (tick_ms && st != S_IDLE) begin
                if (st == S_HOME && at_home) begin
                    st  <= S_IDLE;
                    pos <= 10'd0;
                end else if (remain == 12'd0) begin
                    st  <= S_IDLE;
                    if (st == S_HOME) pos <= 10'd0;
                end else if (wait_ms + 5'd1 >= interval) begin
                    wait_ms <= 5'd0;
                    phase   <= phase + 2'd1;
                    pos     <= (pos == STEPS_PER_REV - 1) ? 10'd0 : pos + 10'd1;
                    remain  <= remain - 12'd1;
                end else begin
                    wait_ms <= wait_ms + 5'd1;
                end
            end
        end
    end
endmodule
