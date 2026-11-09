// 서보모터: 현재 포신 각도를 실제로 가리킴 (7주차 PWM)
//   주기 20 ms, 펄스 폭 = MIN_US(0°) ~ MAX_US(180°) 사이 직선 (7주차 자료: 0.7 ms ~ 2.3 ms)
//   각도는 프레임 틱마다 최대 8°씩 목표를 따라가요 (시뮬레이터와 같음)
//   보드마다 기준 펄스 폭이 조금씩 달라서 MIN_US / MAX_US 를 보드에서 맞춰 보세요
module servo_ctrl #(
    parameter integer CLK_HZ = 1_000_000,
    parameter integer MIN_US = 700,
    parameter integer MAX_US = 2300,
    parameter integer PERIOD_US = 20000,
    parameter integer SLEW = 8
) (
    input  wire       clk,
    input  wire       rst,
    input  wire       tick_frame,
    input  wire [7:0] target_deg,    // 0~180
    output reg  [7:0] cur_deg,
    output reg        servo
);
    localparam integer US = CLK_HZ / 1_000_000;   // 1 us 당 클럭 수

    always @(posedge clk) begin
        if (rst) begin
            cur_deg <= 8'd90;
        end else if (tick_frame) begin
            if (target_deg > cur_deg + SLEW)        cur_deg <= cur_deg + SLEW;
            else if (target_deg + SLEW < cur_deg)   cur_deg <= cur_deg - SLEW;
            else                                    cur_deg <= target_deg;
        end
    end

    // 펄스 폭 (us) = MIN + deg * (MAX-MIN) / 180
    wire [19:0] pulse_us = MIN_US + (cur_deg * (MAX_US - MIN_US)) / 180;

    reg [23:0] cnt;
    always @(posedge clk) begin
        if (rst) begin
            cnt   <= 24'd0;
            servo <= 1'b0;
        end else begin
            cnt   <= (cnt >= PERIOD_US * US - 1) ? 24'd0 : cnt + 24'd1;
            servo <= (cnt < pulse_us * US);
        end
    end
endmodule
