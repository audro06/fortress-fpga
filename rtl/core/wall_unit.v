// 가운데 엄폐물 (블록 3개)
//   블록0 = 아랫줄 7칸, 블록1 = 아랫줄 8칸, 블록2 = 윗줄(2층 탑) 7칸 또는 8칸
//   체력 3 온전 -> 2 금 감 -> 1 잔해 -> 0 무너짐
//   아래 블록이 무너지면 윗 블록이 아래로 떨어짐 (윗 블록 체력이 아래 칸으로 옮겨감)
//   판 배치(layout, 판마다 난수): 0 = 낮은 벽 2개, 1 = 7칸 위 탑, 2 = 8칸 위 탑
module wall_unit (
    input  wire       clk,
    input  wire       rst,
    input  wire       init,
    input  wire       enable,        // DIP8: 가운데 벽 사용
    input  wire [1:0] layout,
    input  wire       hit,           // 포탄에 맞음 (얼음 제외)
    input  wire [1:0] hit_idx,
    input  wire       quake,         // 지진: 모든 블록 한 단계씩
    output wire [5:0] wall_hp,       // {블록2, 블록1, 블록0}
    output reg        wall2_col,     // 0 = 7칸, 1 = 8칸
    output wire       hit_breaks     // 지금 hit_idx 블록이 맞으면 무너짐 (체력 1)
);
    reg [1:0] hp [0:2];

    assign wall_hp    = {hp[2], hp[1], hp[0]};
    assign hit_breaks = (hp[hit_idx] == 2'd1);

    // 한 단계 깎은 다음 떨어짐 처리
    reg [1:0] n0, n1, n2;
    always @(*) begin
        n0 = hp[0]; n1 = hp[1]; n2 = hp[2];
        if (quake) begin
            if (n0 != 2'd0) n0 = n0 - 2'd1;
            if (n1 != 2'd0) n1 = n1 - 2'd1;
            if (n2 != 2'd0) n2 = n2 - 2'd1;
        end else if (hit) begin
            case (hit_idx)
                2'd0: if (n0 != 2'd0) n0 = n0 - 2'd1;
                2'd1: if (n1 != 2'd0) n1 = n1 - 2'd1;
                default: if (n2 != 2'd0) n2 = n2 - 2'd1;
            endcase
        end
        // settleWalls: 윗 블록 아래 칸이 비면 떨어짐
        if (n2 != 2'd0) begin
            if (!wall2_col && n0 == 2'd0) begin n0 = n2; n2 = 2'd0; end
            else if (wall2_col && n1 == 2'd0) begin n1 = n2; n2 = 2'd0; end
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            hp[0] <= 2'd0; hp[1] <= 2'd0; hp[2] <= 2'd0; wall2_col <= 1'b0;
        end else if (init) begin
            hp[0]     <= enable ? 2'd3 : 2'd0;
            hp[1]     <= enable ? 2'd3 : 2'd0;
            hp[2]     <= (enable && layout != 2'd0) ? 2'd3 : 2'd0;
            wall2_col <= (layout == 2'd2);
        end else if (hit || quake) begin
            hp[0] <= n0; hp[1] <= n1; hp[2] <= n2;
        end
    end
endmodule
