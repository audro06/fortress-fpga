// 연출 타이머 모음 (시뮬레이터 G.fx / G.shake / G.rgbF / G.flashMsg / G.parts)
//   폭발      : 칸 하나에 6프레임(4틱씩, 총 24틱) 애니메이션, 넓은 폭발은 양옆에 '*'
//   흔들림    : LCD 표시 이동 명령으로 좌우로 흔듦 (shift = -1/0/+1)
//   LED 번쩍임: Full color LED 색 + 남은 틱
//   알림 문구 : 조준 중 잘못 누른 키 알림 (30틱)
//   불꽃놀이  : 게임 끝 화면 아랫줄 (9틱마다 하나, 24틱 동안 모양이 바뀜, 최대 4개)
module fx_unit (
    input  wire        clk,
    input  wire        rst,
    input  wire        tick_frame,
    input  wire [15:0] rnd,
    input  wire        clear,

    input  wire        explode,
    input  wire [6:0]  ex_x,           // 탄착 x 픽셀 0~79
    input  wire [3:0]  ex_y,           // 탄착 y 픽셀 0~15
    input  wire [1:0]  ex_kind,        // 0 일반, 1 얼음, 2 불
    input  wire        ex_big,
    output reg         fx_on,
    output reg  [4:0]  fx_t,
    output reg  [3:0]  fx_col,         // 칸
    output reg         fx_row,         // 0 윗줄, 1 아랫줄
    output reg  [1:0]  fx_kind,
    output reg         fx_big,

    input  wire        shake_set,
    input  wire [5:0]  shake_val,
    output reg  [5:0]  shake,
    output wire [1:0]  lcd_shift,      // 0 = 그대로, 1 = 오른쪽(+1), 2 = 왼쪽(-1)

    input  wire        rgb_set,
    input  wire [2:0]  rgb_color,
    input  wire [5:0]  rgb_t,
    output reg  [2:0]  rgb_flash_color,
    output reg  [5:0]  rgb_flash_t,

    input  wire        msg_set,
    input  wire        msg_pi,
    input  wire [5:0]  msg_id,
    output reg         msg_on,
    output reg         msg_owner,
    output reg  [5:0]  msg_val,

    input  wire        fireworks,      // 게임 끝 상태일 때 1
    output wire [15:0] fw_cols,        // 불꽃 4개 칸 {c3,c2,c1,c0}
    output wire [19:0] fw_ages,        // 불꽃 4개 나이 {t3..t0} 5비트, 31 = 없음
    output reg         fw_spawn        // 새 불꽃 (효과음용) 1클럭
);
    reg [5:0] msg_t;
    reg [3:0] fw_div;
    reg [3:0] fw_c [0:3];
    reg [4:0] fw_a [0:3];
    reg [1:0] fw_next;

    assign lcd_shift = (shake == 6'd0) ? 2'd0 : (shake[1] ? 2'd1 : 2'd2);
    assign fw_cols = {fw_c[3], fw_c[2], fw_c[1], fw_c[0]};
    assign fw_ages = {fw_a[3], fw_a[2], fw_a[1], fw_a[0]};

    wire [14:0] exm = ex_x * 15'd205;   // x / 5

    integer i;
    always @(posedge clk) begin
        fw_spawn <= 1'b0;
        if (rst || clear) begin
            fx_on <= 1'b0; fx_t <= 5'd0; fx_col <= 4'd0; fx_row <= 1'b1; fx_kind <= 2'd0; fx_big <= 1'b0;
            shake <= 6'd0; rgb_flash_color <= 3'd0; rgb_flash_t <= 6'd0;
            msg_on <= 1'b0; msg_owner <= 1'b0; msg_val <= 6'd0; msg_t <= 6'd0;
            fw_div <= 4'd0; fw_next <= 2'd0;
            for (i = 0; i < 4; i = i + 1) begin fw_c[i] <= 4'd0; fw_a[i] <= 5'd31; end
        end else begin
            if (explode) begin
                fx_on <= 1'b1; fx_t <= 5'd0; fx_col <= exm[13:10]; fx_row <= ex_y[3];
                fx_kind <= ex_kind; fx_big <= ex_big;
            end else if (tick_frame && fx_on) begin
                if (fx_t == 5'd23) fx_on <= 1'b0;
                else               fx_t  <= fx_t + 5'd1;
            end

            if (shake_set)                       shake <= shake_val;
            else if (tick_frame && shake != 0)   shake <= shake - 6'd1;

            if (rgb_set) begin
                rgb_flash_color <= rgb_color; rgb_flash_t <= rgb_t;
            end else if (tick_frame && rgb_flash_t != 0) begin
                rgb_flash_t <= rgb_flash_t - 6'd1;
            end

            if (msg_set) begin
                msg_on <= 1'b1; msg_owner <= msg_pi; msg_val <= msg_id; msg_t <= 6'd30;
            end else if (tick_frame && msg_on) begin
                if (msg_t == 6'd1) msg_on <= 1'b0;
                msg_t <= msg_t - 6'd1;
            end

            if (tick_frame) begin
                for (i = 0; i < 4; i = i + 1)
                    if (fw_a[i] != 5'd31) fw_a[i] <= (fw_a[i] == 5'd23) ? 5'd31 : fw_a[i] + 5'd1;
                if (fireworks) begin
                    if (fw_div == 4'd8) begin
                        fw_div <= 4'd0;
                        fw_c[fw_next] <= rnd[3:0];
                        fw_a[fw_next] <= 5'd0;
                        fw_next <= fw_next + 2'd1;
                        fw_spawn <= 1'b1;
                    end else begin
                        fw_div <= fw_div + 4'd1;
                    end
                end
            end
        end
    end
endmodule
