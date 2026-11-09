// Piezo 효과음 재생기 (6주차 분주로 음 만들기)
//   sfx_req 펄스가 오면 sfx_rom 의 음표 목록을 차례로 재생 (새 요청이 오면 바로 바꿔 재생)
//   효과음이 없을 때 charge_on 이면 파워에 따라 음이 올라가는 충전음 (220 + 110*파워 Hz)
//   enable = 0 (DIP7 OFF) 이면 소리를 끔
module piezo_ctrl #(
    parameter integer CLK_HZ = 1_000_000
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        tick_ms,
    input  wire        enable,
    input  wire        sfx_req,
    input  wire [4:0]  sfx_id,
    input  wire        charge_on,
    input  wire [3:0]  charge_pow,   // 1~8
    input  wire [15:0] rnd,
    output reg         piezo
);
    localparam integer US = CLK_HZ / 1_000_000;

    reg        playing;
    reg [6:0]  addr;
    reg [9:0]  ms_cnt;
    reg [3:0]  noise_cnt;
    reg [13:0] noise_half;

    wire [6:0]  start_addr;
    wire [29:0] entry;
    sfx_rom u_rom (.sfx_id(sfx_id), .start_addr(start_addr), .addr(addr), .entry(entry));

    wire        e_last  = entry[29];
    wire        e_noise = entry[28];
    wire [3:0]  e_mask  = entry[27:24];
    wire [9:0]  e_dur   = entry[23:14];
    wire [13:0] e_half  = entry[13:0];

    // 충전음 반주기 (1 MHz 기준 us) : 500000 / (220 + 110*p)
    reg [13:0] charge_half;
    always @(*) begin
        case (charge_pow)
            4'd1: charge_half = 14'd1515;
            4'd2: charge_half = 14'd1136;
            4'd3: charge_half = 14'd909;
            4'd4: charge_half = 14'd758;
            4'd5: charge_half = 14'd649;
            4'd6: charge_half = 14'd568;
            4'd7: charge_half = 14'd505;
            default: charge_half = 14'd455;
        endcase
    end

    // 재생 순서
    always @(posedge clk) begin
        if (rst) begin
            playing <= 1'b0; addr <= 7'd0; ms_cnt <= 10'd0; noise_cnt <= 4'd0; noise_half <= 14'd1000;
        end else if (sfx_req && sfx_id != 5'd0) begin
            playing <= 1'b1;
            addr    <= start_addr;
            ms_cnt  <= 10'd0;
        end else if (tick_ms) begin
            noise_cnt <= noise_cnt + 4'd1;
            if (noise_cnt == 4'd0)   // 16 ms마다 잡음 주파수를 새로 뽑음
                noise_half <= e_half + (rnd[13:0] & ((14'd1 << e_mask) - 14'd1));
            if (playing) begin
                if (ms_cnt + 10'd1 >= e_dur) begin
                    ms_cnt <= 10'd0;
                    if (e_last) playing <= 1'b0;
                    else        addr <= addr + 7'd1;
                end else begin
                    ms_cnt <= ms_cnt + 10'd1;
                end
            end
        end
    end

    // 지금 낼 음의 반주기 (us). 0 = 무음
    wire [13:0] half_us = playing ? (e_noise ? noise_half : e_half)
                        : (charge_on ? charge_half : 14'd0);

    reg [19:0] cnt;
    always @(posedge clk) begin
        if (rst) begin
            cnt <= 20'd0; piezo <= 1'b0;
        end else if (!enable || half_us == 14'd0) begin
            cnt <= 20'd0; piezo <= 1'b0;
        end else if (cnt + 20'd1 >= half_us * US) begin
            cnt   <= 20'd0;
            piezo <= ~piezo;
        end else begin
            cnt <= cnt + 20'd1;
        end
    end
endmodule
