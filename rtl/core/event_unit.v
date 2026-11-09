// 3턴마다 이벤트 (2턴 유지) - 시뮬레이터 nextTurn() / applyEvent() / endEvent()
//   turn_begin : 턴 시작 처리 (이벤트 남은 턴 줄이기, 끝나면 정리, 새 이벤트 뽑기)
//   apply      : 룰렛이 멈춘 뒤 ev_idx 이벤트를 실제로 적용
//   LAVA   양 진영에 용암 칸 1개씩 (그 칸으로 이동 불가)
//   LOW-G  중력 18 -> 11
//   GUST   바람 ±3~5
//   QUAKE  탱크 ±1칸 밀림 + 벽 한 단계 (1턴만 유지) - 위치·벽은 game_core가 quake_p0/p1 값으로 바꿈
//   FOG    비행 중 포탄 안 보임
//   METEOR '!' 3칸 예고, 이벤트가 끝날 때 유성 낙하 (strike)
module event_unit (
    input  wire        clk,
    input  wire        rst,
    input  wire [15:0] rnd,
    input  wire        reset_game,
    input  wire        events_on,     // DIP4
    input  wire        turn_begin,
    input  wire        setup,         // 첫 턴(이동만)이면 1: 턴 수에 안 셈
    input  wire        apply,
    input  wire        strike_clr,
    input  wire [3:0]  p0_pos,
    input  wire [3:0]  p1_pos,

    output reg         ev_active,
    output reg  [2:0]  ev_id,
    output reg         ev_new,        // 이번 턴 시작에 룰렛을 돌림
    output reg  [2:0]  ev_idx,        // 룰렛 당첨 이벤트
    output wire [1:0]  next_in,       // 다음 이벤트까지 남은 턴 (7세그)
    output reg  [4:0]  lava0,         // {유효, 칸}
    output reg  [4:0]  lava1,
    output reg  [14:0] marks,         // 유성 예고 칸 3개 {유효,칸} x3
    output reg         strike,        // 이번 턴 시작에 유성이 떨어짐
    output reg  [14:0] strike_cells,
    output reg  signed [7:0] wind,
    output reg  [7:0]  grav,
    output wire [3:0]  quake_p0,      // 지진 뒤 위치
    output wire [3:0]  quake_p1
);
    `include "params.vh"

    reg [1:0] cmod;                   // 턴 수 % 3
    reg [1:0] left;
    reg [2:0] last_ev;                // 7 = 없음

    assign next_in = 2'd3 - cmod;

    // ---- 난수 조각
    wire [3:0] ra = rnd[3:0], rb = rnd[7:4], rc = rnd[11:8], rd = rnd[15:12];
    wire [7:0] rlo = rnd[7:0], rhi = rnd[15:8];

    // ---- 새 이벤트 고르기 (직전 이벤트와 겹치면 다른 것으로)
    wire [2:0] pick0 = rlo % 6;
    wire [2:0] pick  = (pick0 == last_ev) ? ((pick0 + 3'd1 + (rhi % 5)) % 6) : pick0;

    // ---- 용암: 진영 안에서 탱크가 없는 칸
    wire [3:0] l0r = ra % 7;                                   // 0~6
    wire [3:0] l0  = (l0r == p0_pos || l0r == p0_pos + 4'd1) ? ((p0_pos + 4'd2 <= 4'd6) ? p0_pos + 4'd2 : p0_pos - 4'd1) : l0r;
    wire [3:0] l1r = 4'd9 + (rb % 7);                          // 9~15
    wire [3:0] l1  = (l1r == p1_pos || l1r == p1_pos - 4'd1) ? ((p1_pos - 4'd2 >= 4'd9) ? p1_pos - 4'd2 : p1_pos + 4'd1) : l1r;

    // ---- 돌풍: ±(3~5)
    wire [7:0] gust_mag = 8'd3 + (rc % 3);
    wire signed [7:0] gust = rd[0] ? gust_mag : -gust_mag;

    // ---- 지진: 각 탱크 -1/0/+1 칸 (진영 안으로 자름)
    wire [1:0] q0 = ra % 3, q1 = rb % 3;
    assign quake_p0 = (q0 == 2'd0) ? ((p0_pos == P1_MIN) ? p0_pos : p0_pos - 4'd1)
                    : (q0 == 2'd2) ? ((p0_pos == P1_MAX) ? p0_pos : p0_pos + 4'd1) : p0_pos;
    assign quake_p1 = (q1 == 2'd0) ? ((p1_pos == P2_MIN) ? p1_pos : p1_pos - 4'd1)
                    : (q1 == 2'd2) ? ((p1_pos == P2_MAX) ? p1_pos : p1_pos + 4'd1) : p1_pos;

    // ---- 유성: 14칸(0~6, 9~15) 중 서로 다른 3칸
    function [3:0] pool;
        input [3:0] i;
        begin
            pool = (i < 4'd7) ? i : i + 4'd2;
        end
    endfunction
    wire [3:0] i0 = rlo % 14;
    wire [3:0] i1 = (i0 + 4'd1 + (rhi % 13)) % 14;
    wire [3:0] i2a = (i0 + 4'd1 + (rnd[11:4] % 13)) % 14;
    wire [3:0] i2b = (i2a == i1) ? ((i2a + 4'd1) % 14) : i2a;
    wire [3:0] i2  = (i2b == i0) ? ((i2b + 4'd1) % 14) : i2b;
    wire [3:0] i2c = (i2 == i1) ? ((i2 + 4'd1) % 14) : i2;   // 한 번 더 비켜감

    // turn_begin 계산
    wire [1:0] cmod_n   = setup ? cmod : ((cmod == 2'd2) ? 2'd0 : cmod + 2'd1);
    wire       ending   = ev_active && (left == 2'd1);
    wire       active_n = ev_active && !ending;

    always @(posedge clk) begin
        if (rst || reset_game) begin
            ev_active <= 1'b0; ev_id <= 3'd0; ev_new <= 1'b0; ev_idx <= 3'd0;
            lava0 <= 5'd0; lava1 <= 5'd0; marks <= 15'd0; strike <= 1'b0; strike_cells <= 15'd0;
            wind <= 8'sd0; grav <= G_NORM; cmod <= 2'd0; left <= 2'd0; last_ev <= 3'd7;
        end else if (turn_begin) begin
            cmod <= cmod_n;
            if (ev_active) left <= left - 2'd1;
            if (ending) begin
                if (ev_id == EV_METEOR) begin
                    strike <= 1'b1;
                    strike_cells <= marks;
                end
                ev_active <= 1'b0;
                lava0 <= 5'd0; lava1 <= 5'd0; marks <= 15'd0; wind <= 8'sd0; grav <= G_NORM;
            end
            if (events_on && !setup && cmod_n == 2'd0 && !active_n) begin
                ev_new  <= 1'b1;
                ev_idx  <= pick;
                last_ev <= pick;
            end else begin
                ev_new <= 1'b0;
            end
        end else if (apply) begin
            ev_active <= 1'b1;
            ev_id     <= ev_idx;
            left      <= (ev_idx == EV_QUAKE) ? 2'd1 : EVENT_LEN;
            case (ev_idx)
                EV_LAVA:   begin lava0 <= {1'b1, l0}; lava1 <= {1'b1, l1}; end
                EV_LOWG:   grav <= G_LOW;
                EV_GUST:   wind <= gust;
                EV_METEOR: marks <= {1'b1, pool(i2c), 1'b1, pool(i1), 1'b1, pool(i0)};
                default:   ;
            endcase
        end else if (strike_clr) begin
            strike <= 1'b0;
        end
    end
endmodule
