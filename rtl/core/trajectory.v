// 포탄 탄도 계산기: 시뮬레이터와 비트 단위로 같은 결과를 냄
//   매 step 펄스마다: vx += wind; vh -= grav; x += vx; h += vh   (모두 1/256 픽셀 단위 정수)
//   화면 좌표: px = x >>> 8,  py = 15 - (h >>> 9)
//   시작값: 속도 ROM[(각도-30)*16 + (ROM파워-1)] = {vx, vh},  포구 ROM[각도-30] = {x 오프셋, h0}
//   use_raw = 1 이면 ROM 대신 start_x/h/vx/vh 로 시작 (유성용)
//   벽·탱크 충돌은 collision 모듈이 px, py로 판정하고, 바깥에서 stop으로 멈춰요.
module trajectory (
    input  wire               clk,
    input  wire               rst,
    input  wire               start,      // 1클럭 펄스: 발사 (이때 아래 입력을 읽음)
    input  wire               step,       // 1클럭 펄스: 한 틱 진행
    input  wire               stop,       // 1클럭 펄스: 비행 종료
    input  wire [5:0]         angle_idx,  // 각도 - 30   (0~60)
    input  wire [3:0]         power_idx,  // ROM 파워 - 1 (0~15)
    input  wire               dir,        // 0: 오른쪽으로 (P1), 1: 왼쪽으로 (P2)
    input  wire [6:0]         pivot_x,    // 포신 회전축 x 픽셀 (P1: 5*대포칸+1, P2: 5*대포칸+3)
    input  wire signed [19:0] start_x,
    input  wire signed [19:0] start_h,
    input  wire signed [19:0] start_vx,
    input  wire signed [19:0] start_vh,
    input  wire               use_raw,
    input  wire signed [7:0]  wind,       // 가로 가속도 (돌풍 이벤트 때만 0 아님)
    input  wire [7:0]         grav,       // 중력 (보통 18, 저중력 11)
    output reg                active,
    output wire signed [9:0]  px,
    output wire signed [9:0]  py,
    output wire               hit_ground, // h <= 0
    output wire               out_of_map  // px < -4 또는 px > 84
);
    reg [23:0] vel_rom [0:975];
    reg [23:0] muz_rom [0:60];
    initial begin
        $readmemh("vel_rom.mem", vel_rom);
        $readmemh("muzzle_rom.mem", muz_rom);
    end

    wire [9:0]  vaddr = {angle_idx, power_idx};       // (각도-30)*16 + (파워-1)
    wire [23:0] vel   = vel_rom[vaddr];
    wire [23:0] muz   = muz_rom[angle_idx];
    wire [19:0] vx0   = {8'd0, vel[23:12]};
    wire [19:0] vh0   = {8'd0, vel[11:0]};
    wire [19:0] mx0   = {8'd0, muz[23:12]};
    wire [19:0] h00   = {8'd0, muz[11:0]};
    wire [19:0] pivot = {5'd0, pivot_x, 8'd0};

    reg  signed [19:0] x, h, vx, vh;
    wire signed [19:0] vx_n = vx + {{12{wind[7]}}, wind};
    wire signed [19:0] vh_n = vh - {12'd0, grav};

    always @(posedge clk) begin
        if (rst) begin
            active <= 1'b0; x <= 20'sd0; h <= 20'sd0; vx <= 20'sd0; vh <= 20'sd0;
        end else if (start) begin
            active <= 1'b1;
            if (use_raw) begin
                x <= start_x; h <= start_h; vx <= start_vx; vh <= start_vh;
            end else begin
                x  <= dir ? (pivot - mx0) : (pivot + mx0);
                h  <= h00;
                vx <= dir ? (20'd0 - vx0) : vx0;
                vh <= vh0;
            end
        end else if (stop) begin
            active <= 1'b0;
        end else if (step && active) begin
            vx <= vx_n;
            vh <= vh_n;
            x  <= x + vx_n;
            h  <= h + vh_n;
        end
    end

    wire signed [19:0] xs = x >>> 8;
    wire signed [19:0] hs = h >>> 9;
    assign px         = xs[9:0];
    assign py         = 10'sd15 - hs[9:0];
    assign hit_ground = h[19] | (h == 20'sd0);
    assign out_of_map = (px < -10'sd4) | (px > 10'sd84);
endmodule
