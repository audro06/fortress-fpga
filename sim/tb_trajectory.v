`timescale 1ns/1ps
// trajectory.v 검증: 시뮬레이터 수식으로 만든 정답(104개)과 비교 (자동 생성: tools/gen_roms.py)
// rom/vel_rom.mem, rom/muzzle_rom.mem 을 시뮬레이션 소스에 같이 추가하세요.
module tb_trajectory;
    reg clk = 1'b0, rst = 1'b1, start = 1'b0, step = 1'b0, stop = 1'b0;
    reg [5:0] angle_idx = 6'd0;
    reg [3:0] power_idx = 4'd0;
    reg dir = 1'b0;
    reg [6:0] pivot_x = 7'd0;
    reg signed [7:0] wind = 8'sd0;
    reg [7:0] grav = 8'd18;
    wire active, hit_ground, out_of_map;
    wire signed [9:0] px, py;

    trajectory dut (
        .clk(clk), .rst(rst), .start(start), .step(step), .stop(stop),
        .angle_idx(angle_idx), .power_idx(power_idx), .dir(dir), .pivot_x(pivot_x),
        .start_x(20'sd0), .start_h(20'sd0), .start_vx(20'sd0), .start_vh(20'sd0), .use_raw(1'b0),
        .wind(wind), .grav(grav),
        .active(active), .px(px), .py(py), .hit_ground(hit_ground), .out_of_map(out_of_map)
    );

    always #5 clk = ~clk;

    integer errors = 0, total = 0, t;

    task check;
        input [5:0] a;
        input [3:0] p;
        input d;
        input [6:0] pv;
        input signed [7:0] w;
        input [7:0] g;
        input integer exp_t;
        input integer exp_px;
        input exp_out;
        begin
            @(negedge clk);
            angle_idx = a; power_idx = p; dir = d; pivot_x = pv; wind = w; grav = g;
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;
            t = 0;
            while (!(out_of_map || hit_ground) && t < 700) begin
                step = 1'b1;
                @(negedge clk);
                step = 1'b0;
                t = t + 1;
            end
            total = total + 1;
            if (t != exp_t || px != exp_px || out_of_map != exp_out) begin
                errors = errors + 1;
                $display("FAIL #%0d: angle %0d power %0d dir %0d wind %0d grav %0d -> ticks %0d (exp %0d) px %0d (exp %0d) out %0b (exp %0b)",
                         total, a + 30, p + 1, d, w, g, t, exp_t, px, exp_px, out_of_map, exp_out);
            end
            stop = 1'b1;
            @(negedge clk);
            stop = 1'b0;
        end
    endtask

    initial begin
        repeat (3) @(negedge clk);
        rst = 1'b0;
        check(6'd0, 4'd0, 1'b0, 7'd6, -8'sd5, 8'd18, 22, 17, 1'b0);
        check(6'd0, 4'd0, 1'b1, 7'd73, 8'sd3, 8'd11, 31, 57, 1'b0);
        check(6'd0, 4'd5, 1'b0, 7'd6, -8'sd5, 8'd18, 28, 32, 1'b0);
        check(6'd0, 4'd5, 1'b1, 7'd73, 8'sd3, 8'd11, 41, 34, 1'b0);
        check(6'd0, 4'd10, 1'b0, 7'd6, -8'sd5, 8'd18, 34, 52, 1'b0);
        check(6'd0, 4'd10, 1'b1, 7'd73, 8'sd3, 8'd11, 52, 1, 1'b0);
        check(6'd0, 4'd15, 1'b0, 7'd6, -8'sd5, 8'd18, 42, 81, 1'b0);
        check(6'd0, 4'd15, 1'b1, 7'd73, 8'sd3, 8'd11, 39, -5, 1'b1);
        check(6'd5, 4'd0, 1'b0, 7'd6, 8'sd0, 8'd11, 33, 27, 1'b0);
        check(6'd5, 4'd0, 1'b1, 7'd73, 8'sd0, 8'd18, 23, 57, 1'b0);
        check(6'd5, 4'd5, 1'b0, 7'd6, 8'sd0, 8'd11, 45, 56, 1'b0);
        check(6'd5, 4'd5, 1'b1, 7'd73, 8'sd0, 8'd18, 30, 38, 1'b0);
        check(6'd5, 4'd10, 1'b0, 7'd6, 8'sd0, 8'd11, 50, 85, 1'b1);
        check(6'd5, 4'd10, 1'b1, 7'd73, 8'sd0, 8'd18, 38, 11, 1'b0);
        check(6'd5, 4'd15, 1'b0, 7'd6, 8'sd0, 8'd11, 38, 86, 1'b1);
        check(6'd5, 4'd15, 1'b1, 7'd73, 8'sd0, 8'd18, 37, -6, 1'b1);
        check(6'd10, 4'd0, 1'b0, 7'd6, 8'sd3, 8'd11, 35, 34, 1'b0);
        check(6'd10, 4'd0, 1'b1, 7'd73, 8'sd4, 8'd18, 25, 62, 1'b0);
        check(6'd10, 4'd5, 1'b0, 7'd6, 8'sd3, 8'd11, 48, 69, 1'b0);
        check(6'd10, 4'd5, 1'b1, 7'd73, 8'sd4, 8'd18, 33, 46, 1'b0);
        check(6'd10, 4'd10, 1'b0, 7'd6, 8'sd3, 8'd11, 45, 85, 1'b1);
        check(6'd10, 4'd10, 1'b1, 7'd73, 8'sd4, 8'd18, 41, 24, 1'b0);
        check(6'd10, 4'd15, 1'b0, 7'd6, 8'sd3, 8'd11, 37, 87, 1'b1);
        check(6'd10, 4'd15, 1'b1, 7'd73, 8'sd4, 8'd18, 50, -5, 1'b1);
        check(6'd15, 4'd0, 1'b0, 7'd6, 8'sd0, 8'd18, 26, 21, 1'b0);
        check(6'd15, 4'd0, 1'b1, 7'd73, -8'sd5, 8'd18, 26, 51, 1'b0);
        check(6'd15, 4'd5, 1'b0, 7'd6, 8'sd0, 8'd18, 35, 40, 1'b0);
        check(6'd15, 4'd5, 1'b1, 7'd73, -8'sd5, 8'd18, 35, 26, 1'b0);
        check(6'd15, 4'd10, 1'b0, 7'd6, 8'sd0, 8'd18, 45, 68, 1'b0);
        check(6'd15, 4'd10, 1'b1, 7'd73, -8'sd5, 8'd18, 43, -6, 1'b1);
        check(6'd15, 4'd15, 1'b0, 7'd6, 8'sd0, 8'd18, 44, 85, 1'b1);
        check(6'd15, 4'd15, 1'b1, 7'd73, -8'sd5, 8'd18, 36, -6, 1'b1);
        check(6'd20, 4'd0, 1'b0, 7'd6, 8'sd4, 8'd18, 27, 26, 1'b0);
        check(6'd20, 4'd0, 1'b1, 7'd73, 8'sd0, 8'd11, 38, 54, 1'b0);
        check(6'd20, 4'd5, 1'b0, 7'd6, 8'sd4, 8'd18, 37, 49, 1'b0);
        check(6'd20, 4'd5, 1'b1, 7'd73, 8'sd0, 8'd11, 55, 25, 1'b0);
        check(6'd20, 4'd10, 1'b0, 7'd6, 8'sd4, 8'd18, 48, 84, 1'b0);
        check(6'd20, 4'd10, 1'b1, 7'd73, 8'sd0, 8'd11, 62, -5, 1'b1);
        check(6'd20, 4'd15, 1'b0, 7'd6, 8'sd4, 8'd18, 41, 87, 1'b1);
        check(6'd20, 4'd15, 1'b1, 7'd73, 8'sd0, 8'd11, 47, -5, 1'b1);
        check(6'd25, 4'd0, 1'b0, 7'd6, -8'sd5, 8'd18, 28, 11, 1'b0);
        check(6'd25, 4'd0, 1'b1, 7'd73, 8'sd3, 8'd11, 40, 65, 1'b0);
        check(6'd25, 4'd5, 1'b0, 7'd6, -8'sd5, 8'd18, 38, 21, 1'b0);
        check(6'd25, 4'd5, 1'b1, 7'd73, 8'sd3, 8'd11, 58, 48, 1'b0);
        check(6'd25, 4'd10, 1'b0, 7'd6, -8'sd5, 8'd18, 50, 37, 1'b0);
        check(6'd25, 4'd10, 1'b1, 7'd73, 8'sd3, 8'd11, 78, 23, 1'b0);
        check(6'd25, 4'd15, 1'b0, 7'd6, -8'sd5, 8'd18, 63, 58, 1'b0);
        check(6'd25, 4'd15, 1'b1, 7'd73, 8'sd3, 8'd11, 79, -5, 1'b1);
        check(6'd30, 4'd0, 1'b0, 7'd6, 8'sd0, 8'd11, 41, 21, 1'b0);
        check(6'd30, 4'd0, 1'b1, 7'd73, 8'sd0, 8'd18, 29, 61, 1'b0);
        check(6'd30, 4'd5, 1'b0, 7'd6, 8'sd0, 8'd11, 61, 46, 1'b0);
        check(6'd30, 4'd5, 1'b1, 7'd73, 8'sd0, 8'd18, 40, 45, 1'b0);
        check(6'd30, 4'd10, 1'b0, 7'd6, 8'sd0, 8'd11, 82, 84, 1'b0);
        check(6'd30, 4'd10, 1'b1, 7'd73, 8'sd0, 8'd18, 53, 21, 1'b0);
        check(6'd30, 4'd15, 1'b0, 7'd6, 8'sd0, 8'd11, 63, 85, 1'b1);
        check(6'd30, 4'd15, 1'b1, 7'd73, 8'sd0, 8'd18, 61, -5, 1'b1);
        check(6'd35, 4'd0, 1'b0, 7'd6, 8'sd3, 8'd11, 42, 30, 1'b0);
        check(6'd35, 4'd0, 1'b1, 7'd73, 8'sd4, 8'd18, 30, 70, 1'b0);
        check(6'd35, 4'd5, 1'b0, 7'd6, 8'sd3, 8'd11, 63, 65, 1'b0);
        check(6'd35, 4'd5, 1'b1, 7'd73, 8'sd4, 8'd18, 41, 62, 1'b0);
        check(6'd35, 4'd10, 1'b0, 7'd6, 8'sd3, 8'd11, 66, 85, 1'b1);
        check(6'd35, 4'd10, 1'b1, 7'd73, 8'sd4, 8'd18, 55, 51, 1'b0);
        check(6'd35, 4'd15, 1'b0, 7'd6, 8'sd3, 8'd11, 57, 86, 1'b1);
        check(6'd35, 4'd15, 1'b1, 7'd73, 8'sd4, 8'd18, 69, 37, 1'b0);
        check(6'd40, 4'd0, 1'b0, 7'd6, 8'sd0, 8'd18, 30, 14, 1'b0);
        check(6'd40, 4'd0, 1'b1, 7'd73, -8'sd5, 8'd18, 30, 55, 1'b0);
        check(6'd40, 4'd5, 1'b0, 7'd6, 8'sd0, 8'd18, 43, 26, 1'b0);
        check(6'd40, 4'd5, 1'b1, 7'd73, -8'sd5, 8'd18, 43, 34, 1'b0);
        check(6'd40, 4'd10, 1'b0, 7'd6, 8'sd0, 8'd18, 56, 43, 1'b0);
        check(6'd40, 4'd10, 1'b1, 7'd73, -8'sd5, 8'd18, 56, 4, 1'b0);
        check(6'd40, 4'd15, 1'b0, 7'd6, 8'sd0, 8'd18, 71, 67, 1'b0);
        check(6'd40, 4'd15, 1'b1, 7'd73, -8'sd5, 8'd18, 55, -5, 1'b1);
        check(6'd45, 4'd0, 1'b0, 7'd6, 8'sd4, 8'd18, 31, 20, 1'b0);
        check(6'd45, 4'd0, 1'b1, 7'd73, 8'sd0, 8'd11, 44, 64, 1'b0);
        check(6'd45, 4'd5, 1'b0, 7'd6, 8'sd4, 8'd18, 43, 35, 1'b0);
        check(6'd45, 4'd5, 1'b1, 7'd73, 8'sd0, 8'd11, 66, 50, 1'b0);
        check(6'd45, 4'd10, 1'b0, 7'd6, 8'sd4, 8'd18, 58, 61, 1'b0);
        check(6'd45, 4'd10, 1'b1, 7'd73, 8'sd0, 8'd11, 91, 27, 1'b0);
        check(6'd45, 4'd15, 1'b0, 7'd6, 8'sd4, 8'd18, 67, 85, 1'b1);
        check(6'd45, 4'd15, 1'b1, 7'd73, 8'sd0, 8'd11, 116, -3, 1'b0);
        check(6'd50, 4'd0, 1'b0, 7'd6, -8'sd5, 8'd18, 31, 0, 1'b0);
        check(6'd50, 4'd0, 1'b1, 7'd73, 8'sd3, 8'd11, 45, 79, 1'b0);
        check(6'd50, 4'd5, 1'b0, 7'd6, -8'sd5, 8'd18, 44, -4, 1'b0);
        check(6'd50, 4'd5, 1'b1, 7'd73, 8'sd3, 8'd11, 67, 84, 1'b0);
        check(6'd50, 4'd10, 1'b0, 7'd6, -8'sd5, 8'd18, 53, -5, 1'b1);
        check(6'd50, 4'd10, 1'b1, 7'd73, 8'sd3, 8'd11, 82, 85, 1'b1);
        check(6'd50, 4'd15, 1'b0, 7'd6, -8'sd5, 8'd18, 61, -5, 1'b1);
        check(6'd50, 4'd15, 1'b1, 7'd73, 8'sd3, 8'd11, 96, 85, 1'b1);
        check(6'd55, 4'd0, 1'b0, 7'd6, 8'sd0, 8'd11, 45, 8, 1'b0);
        check(6'd55, 4'd0, 1'b1, 7'd73, 8'sd0, 8'd18, 31, 70, 1'b0);
        check(6'd55, 4'd5, 1'b0, 7'd6, 8'sd0, 8'd11, 68, 13, 1'b0);
        check(6'd55, 4'd5, 1'b1, 7'd73, 8'sd0, 8'd18, 45, 67, 1'b0);
        check(6'd55, 4'd10, 1'b0, 7'd6, 8'sd0, 8'd11, 93, 21, 1'b0);
        check(6'd55, 4'd10, 1'b1, 7'd73, 8'sd0, 8'd18, 59, 62, 1'b0);
        check(6'd55, 4'd15, 1'b0, 7'd6, 8'sd0, 8'd11, 120, 32, 1'b0);
        check(6'd55, 4'd15, 1'b1, 7'd73, 8'sd0, 8'd18, 75, 56, 1'b0);
        check(6'd60, 4'd0, 1'b0, 7'd6, 8'sd3, 8'd11, 45, 18, 1'b0);
        check(6'd60, 4'd0, 1'b1, 7'd73, 8'sd4, 8'd18, 31, 80, 1'b0);
        check(6'd60, 4'd5, 1'b0, 7'd6, 8'sd3, 8'd11, 68, 33, 1'b0);
        check(6'd60, 4'd5, 1'b1, 7'd73, 8'sd4, 8'd18, 39, 85, 1'b1);
        check(6'd60, 4'd10, 1'b0, 7'd6, 8'sd3, 8'd11, 94, 58, 1'b0);
        check(6'd60, 4'd10, 1'b1, 7'd73, 8'sd4, 8'd18, 39, 85, 1'b1);
        check(6'd60, 4'd15, 1'b0, 7'd6, 8'sd3, 8'd11, 116, 85, 1'b1);
        check(6'd60, 4'd15, 1'b1, 7'd73, 8'sd4, 8'd18, 39, 85, 1'b1);
        if (errors == 0) $display("PASS: all %0d vectors match", total);
        else             $display("FAIL: %0d of %0d vectors mismatch", errors, total);
        $finish;
    end
endmodule
