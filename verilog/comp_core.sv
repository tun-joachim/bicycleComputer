module comp_core (
  //Output
  nDigit,
  SegA,
  SegB,
  SegC,
  SegD,
  SegE,
  SegF,
  SegG,
  DP,

  SCLK,
  SDIN,
  DnC,
  nSCE,
  nRES,

  //Input
  nFork,
  nCrank,
  nMode,
  nTrip,

  nReset,
  Clock
);

timeunit 1ns;
timeprecision 100ps;

output [3:0] nDigit;
output SegA, SegB, SegC, SegD, SegE, SegF, SegG, DP;
output SDIN, SCLK, DnC, nSCE, nRES;

input nReset, Clock, nFork, nCrank, nMode, nTrip;

wire [15:0]fork_time; //Time between fork pulse use to produce rps
wire [15:0]crank_time; //Time between crank pulse use to produce cadence

wire[2:0]mode;
wire trip_Reset;
wire wheelsize_digit_change;
wire wheelsize_value_change;
wire wheelsize_menu;
wire[3:0]addr;
wire clear,update;
wire[2:0]incr;
wire wheelrev_trigger;
logic second_trigger;
wire wheelmenu_trigger;

wire[4:0]Display;
//wire[3:0]Display;
wire[15:0]MemInput;

logic[15:0]mem_read,mem_write;
wire write_enable;

logic[15:0] ram_data_in[1:0];
logic[15:0] ram_data_out[1:0];
logic[3:0] ram_addr[1:0];
logic ram_we [1:0];

//Input Interface
inputCycle SENSOR_INPUT (
   .Clock(Clock),
   .nReset(nReset),
   .nFork(nFork),
   .nCrank(nCrank),
   .fork_time(fork_time),
   .crank_time(crank_time),
   .wheelrev_trigger(wheelrev_trigger),
   .second_trigger(second_trigger)
);

inputbtn BUTTON_INPUT(
   .Clock(Clock),
   .nReset(nReset),
   .nTrip(nTrip),
   .nMode(nMode),
   .mode(mode),
   .trip_Reset(trip_Reset),
   .wheelsize_digit_change(wheelsize_digit_change),
   .wheelsize_value_change(wheelsize_value_change),
   .wheelsize_menu(wheelsize_menu)
);

//Computer and control
control CONTROL(
   .Clock(Clock), 
   .nReset(nReset),
   .mode(mode),
   .trip_Reset(trip_Reset),
   .wheelsize_menu(wheelsize_menu),
   .wheelsize_digit_change(wheelsize_digit_change),
   .wheelsize_value_change(wheelsize_value_change),
   .displayMode(Display),
   .wheelmenu_trigger(wheelmenu_trigger),
   .clear(clear),
   .update(update), 
   .incr(incr)
);

modeCal MODECAL(
    .Clock              (Clock), 
    .nReset             (nReset),
    .fork_time          (fork_time), 
    .crank_time         (crank_time),
    .addr               (addr),
    .mem_read           (mem_read),
    .clear              (clear), 
    .update             (update),
    .incr               (incr),
    .wheelrev_trigger   (wheelrev_trigger),
    .second_trigger     (second_trigger),
    .wheelmenu_trigger  (wheelmenu_trigger),
    .mem_write          (mem_write),
    .write_enable       (write_enable),
    .displayMode        (Display)
);

wire [4:0] Display_ram;

//Memory
memory RAM(
  //Output
  .data_out (ram_data_out),

  //Input
  .data_in  (ram_data_in),
  .addr     (ram_addr),
  .we       (ram_we),
  .Clock    (Clock),
  .nReset   (nReset)
);

assign ram_data_in[0] = mem_write;
assign ram_data_in[1] = 0;
assign mem_read = ram_data_out[0];
assign MemInput = ram_data_out[1];
assign ram_addr[0] = addr;
assign ram_addr[1] = Display_ram;
assign ram_we[0] = write_enable;
assign ram_we[1] = 0;
assign Display_ram = (Display==5'd0) ? 5'd0
		   : (Display==5'd1)	? 5'd1
		   : (Display==5'd2)	? 5'd2
		   : (Display==5'd3)	? 5'd3
		   : (Display==5'd4)	? 5'd4
		   : (Display==5'd5)	? 5'd5
		   : (Display==5'd6) ? 5'd7
		   : (Display==5'd7) ? 5'd7
		   : (Display==5'd8) ? 5'd7
		   : (Display==5'd9)	? 5'd8
		   : (Display==5'd10)? 5'd8
		   : (Display==5'd11)? 5'd8
		   : (Display==5'd12)? 5'd9
		   : (Display==5'd13)? 5'd9
		   : (Display==5'd14)? 5'd9
		   : (Display==5'd15)? 5'd10
		   : (Display==5'd16)? 5'd10
		   : (Display==5'd17)? 5'd10
		   			: 5'd0;

//LED and LCD Interface
led_displays LED(
     //Output
  .nDigit   (nDigit),
  .SegA     (SegA),
  .SegB     (SegB),
  .SegC     (SegC),
  .SegD     (SegD),
  .SegE     (SegE),
  .SegF     (SegF),
  .SegG     (SegG),
  .DP       (DP),

  //Input
  .MemInput (MemInput),
  .display  (Display),
  .Clock    (Clock),
  .nReset   (nReset)
);

lcd_displays LCD(
  .SDIN(SDIN),
  .SCLK(SCLK),
  .DnC(DnC),
  .nRES(nRES),
  .nSCE(nSCE),

  .MemInput (MemInput),
  .display  (Display),
  .Clock    (Clock),
  .nReset   (nReset)
);
  
endmodule
