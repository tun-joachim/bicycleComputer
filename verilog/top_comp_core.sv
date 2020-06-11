module top_comp_core(
  //Output
  SCLK,
  SDIN,
  DnC,
  nSCE,
  nRES,
  rst_led,
  pulse_led,

  //Input
  nMode,
  nTrip,
  Reset,
  Clock
);

output  SCLK;
output  SDIN;
output  DnC;
output  nSCE;
output  nRES;
output  rst_led;
output  pulse_led;

input  nMode;
input  nTrip;
input  Reset;
input  Clock;

wire clk_50M__12_8M;
wire clk_12_8M__12_8K;

wire nFork;
wire nCrank;

reg [13:0] CrankCount, ForkCount, clkdiv1;
reg [9:0] clkdiv;
reg toggle;

PLL_50M_12_8M ppl (
  .refclk(Clock),
  .rst(!Reset),
  .outclk_0(clk_50M__12_8M)
);


comp_core inst (
  //Output
  .nDigit(nDigit),
  .SegA(),
  .SegB(),
  .SegC(),
  .SegD(),
  .SegE(),
  .SegF(),
  .SegG(),
  .DP(),
  .SCLK(SCLK),
  .SDIN(SDIN),
  .DnC(DnC),
  .nSCE(nSCE),
  .nRES(nRES),

  //Input
  .nFork(nFork),
  .nCrank(nCrank),
  .nMode(nMode),
  .nTrip(nTrip),

  .nReset(Reset),
  .Clock(clk_12_8M__12_8K)
);

always_ff @ (posedge clk_12_8M__12_8K or negedge Reset)
if(!Reset) ForkCount <= 14'd0;
else if(ForkCount==14'd4941) ForkCount <= 14'd0;
else ForkCount <= ForkCount + 14'd1;

always_ff @ (posedge clk_12_8M__12_8K or negedge Reset)
if(!Reset) CrankCount <= 14'd0;
else if(CrankCount==14'd7680) CrankCount <= 14'd0;
else CrankCount <= CrankCount + 14'd1;

always_ff @ (posedge clk_50M__12_8M or negedge Reset)
if(!Reset) clkdiv <= 10'd0;
else if(clkdiv==10'd1000) clkdiv <= 10'd0;
else clkdiv <= clkdiv + 10'd1;

always_ff @ (posedge clk_12_8M__12_8K or negedge Reset)
if(!Reset) clkdiv1 <= 14'd0;
else if(clkdiv1==14'd12800) clkdiv1 <= 14'd0;
else clkdiv1 <= clkdiv1 + 14'd1;

always_ff @ (posedge clk_12_8M__12_8K or negedge Reset)
if(!Reset) toggle <= 1'd0;
else if(clkdiv1==14'd12800) toggle <= ~toggle;
else toggle <= toggle;

assign nFork=ForkCount<=14'd26; // 2ms on every 386ms
assign nCrank=CrankCount<=14'd51; // 4ms on every 600ms
assign clk_12_8M__12_8K=(clkdiv < 10'd500);
assign pulse_led=toggle;
assign rst_led = Reset;

endmodule
