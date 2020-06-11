///////////////////////////////////////////////////////////////////////
//
// LCD display module
//
// Display module information:
//   Type: Nokia 5110 48 x 84 px
//   Driver chip: Philips PCD8544
//   Transfer mode CPOL = 0 CPHA = 0
//
//   Ports:
//     SDIN (Input)
//       Serial Data. Sample at positive edge of SCLK.
//     SCLK (Input)
//       Clock for Serial Data. Max speed is 4Mbits/s.
//     DnC (Input)
//       Data = 1, Command = 0. Read at the 8th bit.
//     nRES (Input - Active Low)
//       When nSCE = 1 initialises the lcd. nSCE = 0 clears the
//       current bit transmission and reads the first bit on
//       rising edge of nRES.
//     nSCE (Input - Active Low)
//       Chip Enable to allow serial comms to the lcd. Set to 0
//       when finished.
//
//   Protocol:
//     Data is streamed with MSB(DB7) first. Each data is 1 byte.
//     Each data stream must have the header byte to be the function
//     set which contains bit H to be set either 1 or 0.
//     e.i:
//       Change LCD settings (DnC = 0)
//       1st byte   2nd byte   3rd byte   4th byte
//     | func H=1 | bias sys | set Vop  | temp ctrl |
//       Write to LCD RAM (DnC = 0)
//       1st byte   2nd byte    3rd byte   4th byte
//     | func H=0 | disp ctrl | X addr   | Y addr   |
//       (DnC=1)
//       5th byte   6th byte   7th byte
//     | Wr Data  | Wr Data  | Wr Data  |  .cont
//
//     Instructions:
//       (DnC = 0)
//         NOP       -> 8'b0000_0000
//         Func Set  -> 8'b0010_0PVH
//           P = LCD power down
//           V = Vertical addressing
//           H = instruction type
//         (H = 0)
//           Disp Ctrl -> 8'b0000_1D0E
//             D & E
//               00 display blank
//               10 normal mode
//               01 all display segment on
//               11 inverse video mode
//           Y addr    -> 8'b0100_0YYY
//             0<=Y<=5
//           X addr    -> 8'b1XXX_XXXX
//             0<=X<=83
//         (H = 1)
//           Temp Ctrl -> 8'b0000_01TT
//             T = Temperature coeff
//           Bias Sys  -> 8'b0001_0BBB
//             B = Set bias system
//           Set Vop   -> 8'b1VVV_VVVV
//             V = write Vop to reg
//       (DnC = 1)
//         Wr Data   -> 8'bDDDD_DDDD
//           D = Pixel Data
//
///////////////////////////////////////////////////////////////////////

module lcd_displays(
  // Outputs
  SDIN,
  SCLK,
  DnC,
  nRES,
  nSCE,

  // Inputs
  MemInput,
  display,
  Clock,
  nReset
);

typedef enum logic [5:0] {SPI_IDLE, SPI_TRANSMIT} spi_t;
spi_t spi_state, spi_state_prev;

typedef enum logic [5:0] {LCD_RESET, LCD_SETUP, LCD_IDLE, LCD_DRAW_METRIC_TITLE, LCD_DRAW_METRIC_VALUE} lcd_t;
lcd_t lcd_state, lcd_state_prev;

typedef enum logic [4:0] {
  ODOMETER, TRIP_TIMER, SPEEDOMETER, CADENCE, CALORIES, AVE_SPEED, WHEEL_2, WHEEL_1, WHEEL_0, WEIGHT_2, WEIGHT_1, WEIGHT_0, HEIGHT_2, HEIGHT_1, HEIGHT_0, AGE_1, AGE_0, GENDER
} display_t;

///---------------------------------------------------------------------
//  Signal type goes here.
///---------------------------------------------------------------------

output SDIN;
output SCLK;
output DnC;
output nRES;
output nSCE;

input [15:0] MemInput;
input [4:0] display;
display_t Display;
input Clock;
input nReset;

// Constants
wire [7:0] byte_temp_ctrl = 8'b0000_0101;
wire [7:0] byte_bias_sys  = 8'b0001_0011;
wire [7:0] byte_set_vop   = 8'b1000_0001;

wire [31:0] alphanumeric_0 = {8'h7C, 8'h82, 8'h82, 8'h7C};
wire [31:0] alphanumeric_1 = {8'h80, 8'hFE, 8'h84, 8'h88};
wire [31:0] alphanumeric_2 = {8'h8C, 8'h92, 8'hA2, 8'hCC};
wire [31:0] alphanumeric_3 = {8'h6C, 8'h92, 8'h82, 8'h44};
wire [31:0] alphanumeric_4 = {8'hFE, 8'h12, 8'h14, 8'h18};
wire [31:0] alphanumeric_5 = {8'h62, 8'h92, 8'h92, 8'h5E};
wire [31:0] alphanumeric_6 = {8'h64, 8'h92, 8'h92, 8'h7C};
wire [31:0] alphanumeric_7 = {8'h06, 8'h1A, 8'hE2, 8'h02};
wire [31:0] alphanumeric_8 = {8'h6C, 8'h92, 8'h92, 8'h6C};
wire [31:0] alphanumeric_9 = {8'h7C, 8'h92, 8'h92, 8'h4C};
wire [31:0] alphanumeric_A = {8'hFC, 8'h12, 8'h12, 8'hFC};
wire [31:0] alphanumeric_C = {8'h44, 8'h82, 8'h82, 8'h7C};
wire [31:0] alphanumeric_D = {8'h7C, 8'h82, 8'h82, 8'hFE};
wire [31:0] alphanumeric_E = {8'h82, 8'h92, 8'h92, 8'hFE};
wire [31:0] alphanumeric_F=  {8'h02, 8'h12, 8'h12, 8'hFE};
wire [31:0] alphanumeric_G = {8'h74, 8'h92, 8'h82, 8'h7C};
wire [31:0] alphanumeric_I = {8'h82, 8'h82, 8'hFE, 8'h82};
wire [31:0] alphanumeric_L = {8'h80, 8'h80, 8'h80, 8'hFE};
wire [31:0] alphanumeric_M = {8'h82, 8'h92, 8'h92, 8'hED};
wire [31:0] alphanumeric_P = {8'h0C, 8'h12, 8'h12, 8'hFE};
wire [31:0] alphanumeric_R = {8'h8C, 8'h52, 8'h32, 8'hFE};
wire [31:0] alphanumeric_S = {8'h64, 8'h92, 8'h92, 8'h4C};
wire [31:0] alphanumeric_T = {8'h02, 8'h02, 8'hFE, 8'h02};
wire [31:0] alphanumeric_V = {8'h1C, 8'h60, 8'h80, 8'h7E};

wire [31:0] alphanumeric_colon = {8'h00, 8'h00, 8'h28, 8'h00};
wire [31:0] alphanumeric_dot   = {8'h00, 8'h00, 8'h80, 8'h00};


reg [7:0] msg_buff [7:0];
reg [3:0] msg_len;
reg [3:0] curr_msg;
reg       lcd_reset_wait;
reg [12:0] lcd_setup_wait;

wire      serial_data_on;
wire      serial_clk_on;

reg [2:0] byte_counter;

reg [3:0] letter_num;

wire MEMRefreshTrig;
wire DISPRefreshTrig;

reg [15:0] MemData, TruncData;
reg [4:0] Count;
reg [3:0] Digit [6:0]; // Digit = {Digit0,Digit1,Digit2,NULL,Ones,Tens,Hundreds}

display_t DisplayPrev;
///---------------------------------------------------------------------
//  Sequential block goes here.
///---------------------------------------------------------------------

// Update Display Logic
always_ff @ (posedge Clock or negedge nReset)
if (!nReset) begin
  Digit[0] <= 4'd0;
  Digit[1] <= 4'd0;
  Digit[2] <= 4'd0;
end else begin
  if (Count == 4'd0) case(Display)
    ODOMETER: begin
      if (MemData[15:4] < 12'd100) begin
        Digit[0] <= MemData[3:0];
        Digit[1] <= Digit[4];
        Digit[2] <= Digit[5];
      end
      else begin  // >100km
        Digit[0] <= Digit[4];
        Digit[1] <= Digit[5];
        Digit[2] <= Digit[6];
      end
    end
    TRIP_TIMER: begin
      Digit[0] <= Digit[4]; // ones_minute
      Digit[1] <= Digit[5]; // tens_minute
      Digit[2] <= Digit[6]; // hours
    end
    SPEEDOMETER: begin
      Digit[0] <= Digit[4];
      Digit[1] <= Digit[5];
      Digit[2] <= Digit[6];
    end
    CADENCE: begin
      Digit[0] <= Digit[4];
      Digit[1] <= Digit[5];
      Digit[2] <= Digit[6];
    end
    CALORIES: begin
      Digit[0] <= Digit[4];
      Digit[1] <= Digit[5];
      Digit[2] <= Digit[6];
    end
    AVE_SPEED: begin
      Digit[0] <= Digit[4];
      Digit[1] <= Digit[5];
      Digit[2] <= Digit[6];
    end
    WHEEL_2, WHEEL_1, WHEEL_0: begin
      Digit[0] <= Digit[4];
      Digit[1] <= Digit[5];
      Digit[2] <= Digit[6];
    end
    WEIGHT_2, WEIGHT_1, WEIGHT_0: begin
      Digit[0] <= Digit[4];
      Digit[1] <= Digit[5];
      Digit[2] <= Digit[6];
    end
    HEIGHT_2, HEIGHT_1, HEIGHT_0: begin
      Digit[0] <= Digit[4];
      Digit[1] <= Digit[5];
      Digit[2] <= Digit[6];
    end
    AGE_1, AGE_0: begin
      Digit[0] <= Digit[4];
      Digit[1] <= Digit[5];
      Digit[2] <= Digit[6];
    end
    GENDER: begin
      Digit[0] <= Digit[4];
      Digit[1] <= Digit[5];
      Digit[2] <= Digit[6];
    end
    default: begin
      Digit[0] <= Digit[0];
      Digit[1] <= Digit[1];
      Digit[2] <= Digit[2];
    end
  endcase
  else begin
    Digit[0] <= Digit[0];
    Digit[1] <= Digit[1];
    Digit[2] <= Digit[2];
  end
end

// BCD. Updated on MEMRefreshTrig
always_ff @ (posedge Clock or negedge nReset)
if (!nReset) begin
  DisplayPrev <= ODOMETER;
  Count <= 4'd10;
  Digit[6] <= 4'd0;
  Digit[5] <= 4'd0;
  Digit[4] <= 4'd0;
end else if (MEMRefreshTrig) begin
  DisplayPrev <= Display;
  case (Display)
    ODOMETER:
      Count <= 5'd10;
    TRIP_TIMER:
      Count <= 5'd6;
    SPEEDOMETER:
      Count <= 5'd16;
    CADENCE:
      Count <= 5'd16;
    AVE_SPEED:
      Count <= 5'd16;
    CALORIES:
      Count <= 5'd16;
    WHEEL_2, WHEEL_1, WHEEL_0:
      Count <= 5'd1;
    WEIGHT_2, WEIGHT_1, WEIGHT_0:
      Count <= 5'd1;
    HEIGHT_2, HEIGHT_1, HEIGHT_0:
      Count <= 5'd1;
    AGE_1, AGE_0:
      Count <= 5'd1;
    GENDER:
      Count <= 5'd1;
    default:
      Count <= 5'd0;
  endcase
  Digit[6] <= 4'd0;
  Digit[5] <= 4'd0;
  Digit[4] <= 4'd0;
end else if (Count != 5'd0)
  case (Display)
    ODOMETER: begin
      // Memory = {2'bStatus,10'bInteger,4'bFraction}
      // Hundred
      if (Digit[6] >= 4'd5) Digit[6][3:1] <= Digit[6][2:0]+3'd3;
      else               Digit[6][3:1] <= Digit[6][2:0];
      // Tens
      if (Digit[5] >= 4'd5) begin
         Digit[5][3:1] <= Digit[5][2:0]+3'd3;
         Digit[6][0]   <= 1'b1;
      end else begin
         Digit[5][3:1] <= Digit[5][2:0];
         Digit[6][0]   <= 1'b0;
      end
      // Ones
      if (Digit[4] >= 4'd5) begin
        Digit[4]    <= {Digit[4][2:0]+3'd3,TruncData[Count+3]}; //TruncData[13:4]
        Digit[5][0] <= 1'b1;
      end else begin
        Digit[4]    <= {Digit[4][2:0],TruncData[Count+3]}; //TruncData[13:4]
        Digit[5][0] <= 1'b0;
      end
      Count <= Count - 5'd1;
    end
    TRIP_TIMER: begin // Trip Timer
      // Memory = {4'bHr,6'bMin,6'bSec}
      // Hundreds
      if (Count > 5'd2)
        if (Digit[6] >= 4'd5) Digit[6] <= {Digit[6][2:0]+3'd3,MemData[Count+9]};
        else               Digit[6] <= {Digit[6][2:0],MemData[Count+9]}; //MemData[15:12]
      // Tens
      if (Digit[5] >= 4'd5) Digit[5][3:1] <= Digit[5][2:0]+3'd3;
      else               Digit[5][3:1] <= Digit[5][2:0];
      // Ones
      if (Digit[4] >= 4'd5) begin
        Digit[4]      <= {Digit[4][2:0]+3'd3,TruncData[Count+5]}; //TruncData[11:6]
        Digit[5][0]   <= 1'b1;
      end else begin
        Digit[4]      <= {Digit[4][2:0],TruncData[Count+5]}; //TruncData[11:6]
        Digit[5][0]   <= 1'b0;
      end
      Count <= Count - 5'd1;
    end
    SPEEDOMETER: begin
      // Memory = {16'dSpeed} Speed = 199 =>  19.9 km/h
      // Hundred
      if (Digit[6] >= 4'd5) Digit[6][3:1] <= Digit[6][2:0]+3'd3;
      else               Digit[6][3:1] <= Digit[6][2:0];
      // Tens
      if (Digit[5] >= 4'd5) begin
         Digit[5][3:1] <= Digit[5][2:0]+3'd3;
         Digit[6][0]   <= 1'b1;
      end else begin
         Digit[5][3:1] <= Digit[5][2:0];
         Digit[6][0]   <= 1'b0;
      end
      // Ones
      if (Digit[4] >= 4'd5) begin
        Digit[4]    <= {Digit[4][2:0]+3'd3,TruncData[Count-1]};
        Digit[5][0] <= 1'b1;
      end else begin
        Digit[4]    <= {Digit[4][2:0],TruncData[Count-1]};
        Digit[5][0] <= 1'b0;
      end
      Count <= Count - 5'd1;
    end
    CADENCE: begin
      // Memory = {16'dRPM}
      // Hundred
      if (Digit[6] >= 4'd5) Digit[6][3:1] <= Digit[6][2:0]+3'd3;
      else               Digit[6][3:1] <= Digit[6][2:0];
      // Tens
      if (Digit[5] >= 4'd5) begin
         Digit[5][3:1] <= Digit[5][2:0]+3'd3;
         Digit[6][0]   <= 1'b1;
      end else begin
         Digit[5][3:1] <= Digit[5][2:0];
         Digit[6][0]   <= 1'b0;
      end
      // Ones
      if (Digit[4] >= 4'd5) begin
        Digit[4]    <= {Digit[4][2:0]+3'd3,TruncData[Count-1]};
        Digit[5][0] <= 1'b1;
      end else begin
        Digit[4]    <= {Digit[4][2:0],TruncData[Count-1]};
        Digit[5][0] <= 1'b0;
      end
      Count <= Count - 5'd1;
    end
    CALORIES: begin
      // Memory = {16'dKcal}
      // Hundred
      if (Digit[6] >= 4'd5) Digit[6][3:1] <= Digit[6][2:0]+3'd3;
      else               Digit[6][3:1] <= Digit[6][2:0];
      // Tens
      if (Digit[5] >= 4'd5) begin
         Digit[5][3:1] <= Digit[5][2:0]+3'd3;
         Digit[6][0]   <= 1'b1;
      end else begin
         Digit[5][3:1] <= Digit[5][2:0];
         Digit[6][0]   <= 1'b0;
      end
      // Ones
      if (Digit[4] >= 4'd5) begin
        Digit[4]    <= {Digit[4][2:0]+3'd3,TruncData[Count-1]};
        Digit[5][0] <= 1'b1;
      end else begin
        Digit[4]    <= {Digit[4][2:0],TruncData[Count-1]};
        Digit[5][0] <= 1'b0;
      end
      Count <= Count - 5'd1;
    end
    AVE_SPEED: begin
      // Memory = {16'dSpeed} Speed = 199 =>  19.9 km/h
      // Hundred
      if (Digit[6] >= 4'd5) Digit[6][3:1] <= Digit[6][2:0]+3'd3;
      else               Digit[6][3:1] <= Digit[6][2:0];
      // Tens
      if (Digit[5] >= 4'd5) begin
         Digit[5][3:1] <= Digit[5][2:0]+3'd3;
         Digit[6][0]   <= 1'b1;
      end else begin
         Digit[5][3:1] <= Digit[5][2:0];
         Digit[6][0]   <= 1'b0;
      end
      // Ones
      if (Digit[4] >= 4'd5) begin
        Digit[4]    <= {Digit[4][2:0]+3'd3,TruncData[Count-1]};
        Digit[5][0] <= 1'b1;
      end else begin
        Digit[4]    <= {Digit[4][2:0],TruncData[Count-1]};
        Digit[5][0] <= 1'b0;
      end
      Count <= Count - 5'd1;
    end
    WHEEL_2, WHEEL_1, WHEEL_0: begin
      Digit[4] <= TruncData[3:0];
      Digit[5] <= TruncData[7:4];
      Digit[6] <= TruncData[11:8];
      Count <= Count - 5'd1;
    end
    WEIGHT_2, WEIGHT_1, WEIGHT_0: begin
      Digit[4] <= TruncData[3:0];
      Digit[5] <= TruncData[7:4];
      Digit[6] <= TruncData[11:8];
      Count <= Count - 5'd1;
    end
    HEIGHT_2, HEIGHT_1, HEIGHT_0: begin
      Digit[4] <= TruncData[3:0];
      Digit[5] <= TruncData[7:4];
      Digit[6] <= TruncData[11:8];
      Count <= Count - 5'd1;
    end
    AGE_1, AGE_0: begin
      Digit[4] <= TruncData[3:0];
      Digit[5] <= TruncData[7:4];
      Digit[6] <= 4'd0;
      Count <= Count - 5'd1;
    end
    GENDER: begin
      Digit[4] <= {3'd0,TruncData[0]};
      Digit[5] <= {3'd0,TruncData[0]};
      Digit[6] <= 4'd0;
      Count <= Count - 5'd1;
    end
    default: begin
      Count <= Count;
      Digit[4] <= Digit[4];
      Digit[5] <= Digit[5];
      Digit[6] <= Digit[6];
    end
  endcase
else begin
  Count <= Count;
  Digit[4] <= Digit[4];
  Digit[5] <= Digit[5];
  Digit[6] <= Digit[6];
end

// Update MemData & TruncData
always_ff @ (posedge Clock or negedge nReset)
if (!nReset) begin
  MemData <= 16'd0;
  TruncData <= 16'd0;
end
else if (MEMRefreshTrig) begin
  MemData <= MemInput;
  case (Display)
    ODOMETER: TruncData <= MemInput;
    TRIP_TIMER: TruncData <= MemInput;
    SPEEDOMETER:
      if (MemInput < 16'd1_000)
        TruncData <= MemInput;
      else
        TruncData <= MemInput/16'd10;
    CADENCE:
      if (MemInput < 16'd10_000)
        TruncData <= MemInput/16'd10;
      else
        TruncData <= MemInput/16'd100;
    CALORIES:
      if (MemInput < 16'd10_000)
        TruncData <= MemInput/16'd10;
      else
        TruncData <= MemInput/16'd100;
    AVE_SPEED:
      if (MemInput < 16'd1_000)
        TruncData <= MemInput;
      else
        TruncData <= MemInput/16'd10;
    WHEEL_2, WHEEL_1, WHEEL_0:
      TruncData <= {4'd0,MemInput[11:0]};
    WEIGHT_2, WEIGHT_1, WEIGHT_0:
      TruncData <= {4'd0,MemInput[11:0]};
    HEIGHT_2, HEIGHT_1, HEIGHT_0:
      TruncData <= {4'd0,MemInput[11:0]};
    AGE_1, AGE_0:
      TruncData <= {8'd0,MemInput[7:0]};
    GENDER:
      TruncData <= {15'd0,MemInput[9]};
  endcase
end
else begin
  MemData <= MemData;
  TruncData <= TruncData;
end

// SPI state machine
always_ff @ (posedge Clock or negedge nReset)
if(!nReset) begin
  spi_state <= SPI_IDLE;
end else begin
  case(spi_state)
    SPI_IDLE: begin
      if((lcd_state == LCD_IDLE) | (lcd_state == LCD_RESET))
        spi_state <= SPI_IDLE;
      else
        spi_state <= SPI_TRANSMIT;
    end
    SPI_TRANSMIT: begin
      case(lcd_state)
        LCD_SETUP: begin
          if((curr_msg == 10'd1) & (byte_counter == 3'd0))
            if(lcd_setup_wait == 10'd0)
              spi_state <= SPI_IDLE;
            else
              spi_state <= SPI_TRANSMIT;
          else
            spi_state <= SPI_TRANSMIT;
        end
        LCD_DRAW_METRIC_TITLE: begin
          if(letter_num == 4'd0)
            spi_state <= SPI_IDLE;
          else
            spi_state <= SPI_TRANSMIT;
        end
        LCD_DRAW_METRIC_VALUE: begin
          if(letter_num == 4'd0)
            spi_state <= SPI_IDLE;
          else
            spi_state <= SPI_TRANSMIT;
        end
        default: begin
          spi_state <= SPI_IDLE;
        end
      endcase
    end
    default: begin
      spi_state <= SPI_IDLE;
    end
  endcase
end

// Previous SPI state
always_ff @ (posedge Clock or negedge nReset)
if(!nReset)
  spi_state_prev <= SPI_IDLE;
else
   spi_state_prev <= spi_state;


// LCD state machine
always_ff @ (posedge Clock or negedge nReset)
if(!nReset)
  lcd_state <= LCD_RESET;
else begin
  case(lcd_state)
    LCD_RESET: begin
      if(lcd_reset_wait)
        lcd_state <= LCD_SETUP;
      else
        lcd_state <= LCD_RESET;
    end
    LCD_SETUP: begin
      if((curr_msg == 10'd1)&(byte_counter == 3'd0))
        if(lcd_setup_wait == 10'd0)
            lcd_state <= LCD_IDLE;
          else
            lcd_state <= LCD_SETUP;
      else
        lcd_state <= LCD_SETUP;
    end
    LCD_IDLE: begin
      if(lcd_state_prev == LCD_SETUP)
        lcd_state <= LCD_DRAW_METRIC_TITLE;
      else
        if(lcd_state_prev == LCD_DRAW_METRIC_TITLE)
          lcd_state <= LCD_DRAW_METRIC_VALUE;
        else
          if(DISPRefreshTrig)
            lcd_state <= LCD_DRAW_METRIC_TITLE;
          else
            if(MEMRefreshTrig)
              lcd_state <= LCD_DRAW_METRIC_VALUE;
            else
              lcd_state <= LCD_IDLE;
    end
    LCD_DRAW_METRIC_TITLE: begin
      if((letter_num == 4'd0) & !(lcd_state_prev == LCD_IDLE))
        lcd_state <= LCD_IDLE;
      else
        lcd_state <= LCD_DRAW_METRIC_TITLE;
    end
    LCD_DRAW_METRIC_VALUE: begin
      if((letter_num == 4'd0) & !(lcd_state_prev == LCD_IDLE))
        lcd_state <= LCD_IDLE;
      else
        lcd_state <= LCD_DRAW_METRIC_VALUE;
    end
    default: begin
      lcd_state <= LCD_IDLE;
    end
  endcase
end

// Previous LCD state
always_ff @ (posedge Clock or negedge nReset)
if(!nReset)
  lcd_state_prev <= LCD_RESET;
else
  lcd_state_prev <= lcd_state;


// LCD reset counter
always_ff @ (posedge Clock or negedge nReset)
if(!nReset)
  lcd_reset_wait <= 1'b0;
else
  if(lcd_state == LCD_RESET)
    lcd_reset_wait <= 1'b1;
  else
    lcd_reset_wait <= 1'b0;

// LCD setup counter
always_ff @ (posedge Clock or negedge nReset)
if(!nReset)
  lcd_setup_wait <= 10'd0;
else
  if((lcd_state == LCD_SETUP) & (lcd_state_prev == LCD_RESET) & (lcd_setup_wait == 10'd0))
    lcd_setup_wait <= 13'd4095;
  else
    if(lcd_setup_wait == 10'd0)
      lcd_setup_wait <= 10'd0;
    else
      if(spi_state_prev == SPI_TRANSMIT)
        lcd_setup_wait <= lcd_setup_wait - 10'd1;
      else
        lcd_setup_wait <= lcd_setup_wait;

// message buffer
always_ff @ (posedge Clock or negedge nReset)
if(!nReset) begin
  msg_buff[0] <= 8'd0;
  msg_buff[1] <= 8'd0;
  msg_buff[2] <= 8'd0;
  msg_buff[3] <= 8'd0;
  msg_buff[4] <= 8'd0;
  msg_buff[5] <= 8'd0;
  msg_buff[6] <= 8'd0;
  msg_buff[7] <= 8'd0;
end else begin
  case(lcd_state)
    LCD_SETUP: begin
      if(lcd_setup_wait > 13'd4032) begin
        msg_buff[0] <= 8'b0010_0001;
        msg_buff[1] <= byte_temp_ctrl;
        msg_buff[2] <= byte_bias_sys;
        msg_buff[3] <= byte_set_vop;
        msg_buff[4] <= 8'b0010_0000;
        msg_buff[5] <= 8'b0000_1100;
        msg_buff[6] <= 8'b0100_0000;
        msg_buff[7] <= 8'b1000_0000;
      end
      else begin
        msg_buff[0] <= 8'd0;
        msg_buff[1] <= 8'd0;
        msg_buff[2] <= 8'd0;
        msg_buff[3] <= 8'd0;
        msg_buff[4] <= 8'd0;
        msg_buff[5] <= 8'd0;
        msg_buff[6] <= 8'd0;
        msg_buff[7] <= 8'd0;
      end
    end
    LCD_DRAW_METRIC_TITLE: begin
      case(Display)
        ODOMETER: begin
          case(letter_num)
            4'd7: begin
              msg_buff[0] <= 8'd0;
              msg_buff[1] <= alphanumeric_0[7:0];
              msg_buff[2] <= alphanumeric_0[15:8];
              msg_buff[3] <= alphanumeric_0[23:16];
              msg_buff[4] <= alphanumeric_0[31:24];
              msg_buff[5] <= 8'd0;
            end
            4'd6: begin
              msg_buff[0] <= 8'd0;
              msg_buff[1] <= alphanumeric_D[7:0];
              msg_buff[2] <= alphanumeric_D[15:8];
              msg_buff[3] <= alphanumeric_D[23:16];
              msg_buff[4] <= alphanumeric_D[31:24];
              msg_buff[5] <= 8'd0;
            end
            4'd5: begin
              msg_buff[0] <= 8'd0;
              msg_buff[1] <= alphanumeric_0[7:0];
              msg_buff[2] <= alphanumeric_0[15:8];
              msg_buff[3] <= alphanumeric_0[23:16];
              msg_buff[4] <= alphanumeric_0[31:24];
              msg_buff[5] <= 8'd0;
            end
            4'd4, 4'd3, 4'd2: begin
              msg_buff[0] <= 8'd0;
              msg_buff[1] <= 8'd0;
              msg_buff[2] <= 8'd0;
              msg_buff[3] <= 8'd0;
              msg_buff[4] <= 8'd0;
              msg_buff[5] <= 8'd0;
            end
            4'd1: begin
              msg_buff[0] <= 8'd0;
              msg_buff[1] <= 8'd0;
              msg_buff[2] <= 8'd0;
              msg_buff[3] <= 8'd0;
              msg_buff[4] <= 8'd0;
              msg_buff[5] <= 8'd0;
            end
            4'd0: begin
              msg_buff[0] <= 8'd0;
              msg_buff[1] <= 8'b0010_0000;
              msg_buff[2] <= 8'b0100_0010;
              msg_buff[3] <= 8'b1001_0000;
              msg_buff[4] <= 8'd0;
              msg_buff[5] <= 8'd0;
            end
          endcase
          msg_buff[6] <= 8'd0;
          msg_buff[7] <= 8'd0;
        end
        TRIP_TIMER: begin
          case(letter_num)
            4'd7: begin
              msg_buff[0] <= 8'd0;
              msg_buff[1] <= alphanumeric_T[7:0];
              msg_buff[2] <= alphanumeric_T[15:8];
              msg_buff[3] <= alphanumeric_T[23:16];
              msg_buff[4] <= alphanumeric_T[31:24];
              msg_buff[5] <= 8'd0;
            end
            4'd6: begin
              msg_buff[0] <= 8'd0;
              msg_buff[1] <= alphanumeric_R[7:0];
              msg_buff[2] <= alphanumeric_R[15:8];
              msg_buff[3] <= alphanumeric_R[23:16];
              msg_buff[4] <= alphanumeric_R[31:24];
              msg_buff[5] <= 8'd0;
            end
            4'd5: begin
              msg_buff[0] <= 8'd0;
              msg_buff[1] <= alphanumeric_I[7:0];
              msg_buff[2] <= alphanumeric_I[15:8];
              msg_buff[3] <= alphanumeric_I[23:16];
              msg_buff[4] <= alphanumeric_I[31:24];
              msg_buff[5] <= 8'd0;
            end
            4'd4: begin
              msg_buff[0] <= 8'd0;
              msg_buff[1] <= alphanumeric_P[7:0];
              msg_buff[2] <= alphanumeric_P[15:8];
              msg_buff[3] <= alphanumeric_P[23:16];
              msg_buff[4] <= alphanumeric_P[31:24];
              msg_buff[5] <= 8'd0;
            end
            4'd3, 4'd2: begin
              msg_buff[0] <= 8'd0;
              msg_buff[1] <= 8'd0;
              msg_buff[2] <= 8'd0;
              msg_buff[3] <= 8'd0;
              msg_buff[4] <= 8'd0;
              msg_buff[5] <= 8'd0;
            end
            4'd1: begin
              msg_buff[0] <= 8'd0;
              msg_buff[1] <= 8'd0;
              msg_buff[2] <= 8'd0;
              msg_buff[3] <= 8'd0;
              msg_buff[4] <= 8'd0;
              msg_buff[5] <= 8'd0;
            end
            4'd0: begin
              msg_buff[0] <= 8'd0;
              msg_buff[1] <= 8'b0010_0000;
              msg_buff[2] <= 8'b0100_0010;
              msg_buff[3] <= 8'b1001_0000;
              msg_buff[4] <= 8'd0;
              msg_buff[5] <= 8'd0;
            end
          endcase
          msg_buff[6] <= 8'd0;
          msg_buff[7] <= 8'd0;
        end
        SPEEDOMETER: begin
          case(letter_num)
            4'd7: begin
              msg_buff[0] <= 8'd0;
              msg_buff[1] <= alphanumeric_S[7:0];
              msg_buff[2] <= alphanumeric_S[15:8];
              msg_buff[3] <= alphanumeric_S[23:16];
              msg_buff[4] <= alphanumeric_S[31:24];
              msg_buff[5] <= 8'd0;
            end
            4'd6: begin
              msg_buff[0] <= 8'd0;
              msg_buff[1] <= alphanumeric_P[7:0];
              msg_buff[2] <= alphanumeric_P[15:8];
              msg_buff[3] <= alphanumeric_P[23:16];
              msg_buff[4] <= alphanumeric_P[31:24];
              msg_buff[5] <= 8'd0;
            end
            4'd5: begin
              msg_buff[0] <= 8'd0;
              msg_buff[1] <= alphanumeric_D[7:0];
              msg_buff[2] <= alphanumeric_D[15:8];
              msg_buff[3] <= alphanumeric_D[23:16];
              msg_buff[4] <= alphanumeric_D[31:24];
              msg_buff[5] <= 8'd0;
            end
            4'd4, 4'd3, 4'd2: begin
              msg_buff[0] <= 8'd0;
              msg_buff[1] <= 8'd0;
              msg_buff[2] <= 8'd0;
              msg_buff[3] <= 8'd0;
              msg_buff[4] <= 8'd0;
              msg_buff[5] <= 8'd0;
            end
            4'd1: begin
              msg_buff[0] <= 8'd0;
              msg_buff[1] <= 8'd0;
              msg_buff[2] <= 8'd0;
              msg_buff[3] <= 8'd0;
              msg_buff[4] <= 8'd0;
              msg_buff[5] <= 8'd0;
            end
            4'd0: begin
              msg_buff[0] <= 8'd0;
              msg_buff[1] <= 8'b0010_0000;
              msg_buff[2] <= 8'b0100_0010;
              msg_buff[3] <= 8'b1001_0000;
              msg_buff[4] <= 8'd0;
              msg_buff[5] <= 8'd0;
            end
          endcase
          msg_buff[6] <= 8'd0;
          msg_buff[7] <= 8'd0;
        end
        CADENCE: begin
          case(letter_num)
            4'd7: begin
              msg_buff[0] <= 8'd0;
              msg_buff[1] <= alphanumeric_C[7:0];
              msg_buff[2] <= alphanumeric_C[15:8];
              msg_buff[3] <= alphanumeric_C[23:16];
              msg_buff[4] <= alphanumeric_C[31:24];
              msg_buff[5] <= 8'd0;
            end
            4'd6: begin
              msg_buff[0] <= 8'd0;
              msg_buff[1] <= alphanumeric_A[7:0];
              msg_buff[2] <= alphanumeric_A[15:8];
              msg_buff[3] <= alphanumeric_A[23:16];
              msg_buff[4] <= alphanumeric_A[31:24];
              msg_buff[5] <= 8'd0;
            end
            4'd5: begin
              msg_buff[0] <= 8'd0;
              msg_buff[1] <= alphanumeric_D[7:0];
              msg_buff[2] <= alphanumeric_D[15:8];
              msg_buff[3] <= alphanumeric_D[23:16];
              msg_buff[4] <= alphanumeric_D[31:24];
              msg_buff[5] <= 8'd0;
            end
            4'd4, 4'd3, 4'd2: begin
              msg_buff[0] <= 8'd0;
              msg_buff[1] <= 8'd0;
              msg_buff[2] <= 8'd0;
              msg_buff[3] <= 8'd0;
              msg_buff[4] <= 8'd0;
              msg_buff[5] <= 8'd0;
            end
            4'd1: begin
              msg_buff[0] <= 8'd0;
              msg_buff[1] <= 8'd0;
              msg_buff[2] <= 8'd0;
              msg_buff[3] <= 8'd0;
              msg_buff[4] <= 8'd0;
              msg_buff[5] <= 8'd0;
            end
            4'd0: begin
              msg_buff[0] <= 8'd0;
              msg_buff[1] <= 8'b0010_0000;
              msg_buff[2] <= 8'b0100_0010;
              msg_buff[3] <= 8'b1001_0000;
              msg_buff[4] <= 8'd0;
              msg_buff[5] <= 8'd0;
            end
          endcase
          msg_buff[6] <= 8'd0;
          msg_buff[7] <= 8'd0;
        end
        AVE_SPEED: begin
          case(letter_num)
            4'd7: begin
              msg_buff[0] <= 8'd0;
              msg_buff[1] <= alphanumeric_A[7:0];
              msg_buff[2] <= alphanumeric_A[15:8];
              msg_buff[3] <= alphanumeric_A[23:16];
              msg_buff[4] <= alphanumeric_A[31:24];
              msg_buff[5] <= 8'd0;
            end
            4'd6: begin
              msg_buff[0] <= 8'd0;
              msg_buff[1] <= alphanumeric_V[7:0];
              msg_buff[2] <= alphanumeric_V[15:8];
              msg_buff[3] <= alphanumeric_V[23:16];
              msg_buff[4] <= alphanumeric_V[31:24];
              msg_buff[5] <= 8'd0;
            end
            4'd5: begin
              msg_buff[0] <= 8'd0;
              msg_buff[1] <= alphanumeric_E[7:0];
              msg_buff[2] <= alphanumeric_E[15:8];
              msg_buff[3] <= alphanumeric_E[23:16];
              msg_buff[4] <= alphanumeric_E[31:24];
              msg_buff[5] <= 8'd0;
            end
            4'd4: begin
              msg_buff[0] <= 8'd0;
              msg_buff[1] <= 8'd0;
              msg_buff[2] <= 8'd0;
              msg_buff[3] <= 8'd0;
              msg_buff[4] <= 8'd0;
              msg_buff[5] <= 8'd0;
            end
            4'd3: begin
              msg_buff[0] <= 8'd0;
              msg_buff[1] <= alphanumeric_S[7:0];
              msg_buff[2] <= alphanumeric_S[15:8];
              msg_buff[3] <= alphanumeric_S[23:16];
              msg_buff[4] <= alphanumeric_S[31:24];
              msg_buff[5] <= 8'd0;
            end
            4'd2: begin
              msg_buff[0] <= 8'd0;
              msg_buff[1] <= alphanumeric_P[7:0];
              msg_buff[2] <= alphanumeric_P[15:8];
              msg_buff[3] <= alphanumeric_P[23:16];
              msg_buff[4] <= alphanumeric_P[31:24];
              msg_buff[5] <= 8'd0;
            end
            4'd1: begin
              msg_buff[0] <= alphanumeric_D[7:0];
              msg_buff[1] <= alphanumeric_D[15:8];
              msg_buff[2] <= alphanumeric_D[23:16];
              msg_buff[3] <= alphanumeric_D[31:24];
              msg_buff[4] <= 8'd0;
              msg_buff[5] <= 8'd0;
            end
            4'd0: begin
              msg_buff[0] <= 8'd0;
              msg_buff[1] <= 8'b0010_0000;
              msg_buff[2] <= 8'b0100_0010;
              msg_buff[3] <= 8'b1001_0000;
              msg_buff[4] <= 8'd0;
              msg_buff[5] <= 8'd0;
            end
          endcase
          msg_buff[6] <= 8'd0;
          msg_buff[7] <= 8'd0;
        end
        CALORIES: begin
          case(letter_num)
            4'd7: begin
              msg_buff[0] <= 8'd0;
              msg_buff[1] <= alphanumeric_C[7:0];
              msg_buff[2] <= alphanumeric_C[15:8];
              msg_buff[3] <= alphanumeric_C[23:16];
              msg_buff[4] <= alphanumeric_C[31:24];
              msg_buff[5] <= 8'd0;
            end
            4'd6: begin
              msg_buff[0] <= 8'd0;
              msg_buff[1] <= alphanumeric_A[7:0];
              msg_buff[2] <= alphanumeric_A[15:8];
              msg_buff[3] <= alphanumeric_A[23:16];
              msg_buff[4] <= alphanumeric_A[31:24];
              msg_buff[5] <= 8'd0;
            end
            4'd5: begin
              msg_buff[0] <= 8'd0;
              msg_buff[1] <= alphanumeric_L[7:0];
              msg_buff[2] <= alphanumeric_L[15:8];
              msg_buff[3] <= alphanumeric_L[23:16];
              msg_buff[4] <= alphanumeric_L[31:24];
              msg_buff[5] <= 8'd0;
            end
            4'd4, 4'd3, 4'd2: begin
              msg_buff[0] <= 8'd0;
              msg_buff[1] <= 8'd0;
              msg_buff[2] <= 8'd0;
              msg_buff[3] <= 8'd0;
              msg_buff[4] <= 8'd0;
              msg_buff[5] <= 8'd0;
            end
            4'd1: begin
              msg_buff[0] <= 8'd0;
              msg_buff[1] <= 8'd0;
              msg_buff[2] <= 8'd0;
              msg_buff[3] <= 8'd0;
              msg_buff[4] <= 8'd0;
              msg_buff[5] <= 8'd0;
            end
            4'd0: begin
              msg_buff[0] <= 8'd0;
              msg_buff[1] <= 8'b0010_0000;
              msg_buff[2] <= 8'b0100_0010;
              msg_buff[3] <= 8'b1001_0000;
              msg_buff[4] <= 8'd0;
              msg_buff[5] <= 8'd0;
            end
          endcase
          msg_buff[6] <= 8'd0;
          msg_buff[7] <= 8'd0;
        end
        WHEEL_2, WHEEL_1, WHEEL_0, WEIGHT_2, WEIGHT_1, WEIGHT_0, HEIGHT_2, HEIGHT_1, HEIGHT_0, AGE_1, AGE_0, GENDER: begin
          case(letter_num)
            4'd7: begin
              msg_buff[0] <= 8'd0;
              msg_buff[1] <= alphanumeric_C[7:0];
              msg_buff[2] <= alphanumeric_C[15:8];
              msg_buff[3] <= alphanumeric_C[23:16];
              msg_buff[4] <= alphanumeric_C[31:24];
              msg_buff[5] <= 8'd0;
            end
            4'd6: begin
              msg_buff[0] <= 8'd0;
              msg_buff[1] <= alphanumeric_F[7:0];
              msg_buff[2] <= alphanumeric_F[15:8];
              msg_buff[3] <= alphanumeric_F[23:16];
              msg_buff[4] <= alphanumeric_F[31:24];
              msg_buff[5] <= 8'd0;
            end
            4'd5: begin
              msg_buff[0] <= 8'd0;
              msg_buff[1] <= alphanumeric_G[7:0];
              msg_buff[2] <= alphanumeric_G[15:8];
              msg_buff[3] <= alphanumeric_G[23:16];
              msg_buff[4] <= alphanumeric_G[31:24];
              msg_buff[5] <= 8'd0;
            end
            4'd3: begin
              case(Display)
                WHEEL_2, WHEEL_1, WHEEL_0: begin
                  msg_buff[0] <= 8'd0;
                  msg_buff[1] <= alphanumeric_1[7:0];
                  msg_buff[2] <= alphanumeric_1[15:8];
                  msg_buff[3] <= alphanumeric_1[23:16];
                  msg_buff[4] <= alphanumeric_1[31:24];
                  msg_buff[5] <= 8'd0;
                end
                WEIGHT_2, WEIGHT_1, WEIGHT_0: begin
                  msg_buff[0] <= 8'd0;
                  msg_buff[1] <= alphanumeric_2[7:0];
                  msg_buff[2] <= alphanumeric_2[15:8];
                  msg_buff[3] <= alphanumeric_2[23:16];
                  msg_buff[4] <= alphanumeric_2[31:24];
                  msg_buff[5] <= 8'd0;
                end
                HEIGHT_2, HEIGHT_1, HEIGHT_0: begin
                  msg_buff[0] <= 8'd0;
                  msg_buff[1] <= alphanumeric_3[7:0];
                  msg_buff[2] <= alphanumeric_3[15:8];
                  msg_buff[3] <= alphanumeric_3[23:16];
                  msg_buff[4] <= alphanumeric_3[31:24];
                  msg_buff[5] <= 8'd0;
                end
                AGE_1, AGE_0: begin
                  msg_buff[0] <= 8'd0;
                  msg_buff[1] <= alphanumeric_4[7:0];
                  msg_buff[2] <= alphanumeric_4[15:8];
                  msg_buff[3] <= alphanumeric_4[23:16];
                  msg_buff[4] <= alphanumeric_4[31:24];
                  msg_buff[5] <= 8'd0;
                end
                GENDER: begin
                  msg_buff[0] <= 8'd0;
                  msg_buff[1] <= alphanumeric_5[7:0];
                  msg_buff[2] <= alphanumeric_5[15:8];
                  msg_buff[3] <= alphanumeric_5[23:16];
                  msg_buff[4] <= alphanumeric_5[31:24];
                  msg_buff[5] <= 8'd0;
                end
              endcase
            end
            4'd4, 4'd2: begin
              msg_buff[0] <= 8'd0;
              msg_buff[1] <= 8'd0;
              msg_buff[2] <= 8'd0;
              msg_buff[3] <= 8'd0;
              msg_buff[4] <= 8'd0;
              msg_buff[5] <= 8'd0;
            end
            4'd1: begin
              msg_buff[0] <= 8'd0;
              msg_buff[1] <= 8'd0;
              msg_buff[2] <= 8'd0;
              msg_buff[3] <= 8'd0;
              msg_buff[4] <= 8'd0;
              msg_buff[5] <= 8'd0;
            end
            4'd0: begin
              msg_buff[0] <= 8'd0;
              msg_buff[1] <= 8'b0010_0000;
              msg_buff[2] <= 8'b0100_0010;
              msg_buff[3] <= 8'b1001_0000;
              msg_buff[4] <= 8'd0;
              msg_buff[5] <= 8'd0;
            end
          endcase
          msg_buff[6] <= 8'd0;
          msg_buff[7] <= 8'd0;
        end
      endcase
    end
    LCD_DRAW_METRIC_VALUE: begin
      case(Display)
        ODOMETER: begin
          case(letter_num)
            4'd7, 4'd6: begin
              case(Digit[letter_num-4'd5])
                4'd0: begin
                  msg_buff[1] <= alphanumeric_0[7:0];
                  msg_buff[2] <= alphanumeric_0[15:8];
                  msg_buff[3] <= alphanumeric_0[23:16];
                  msg_buff[4] <= alphanumeric_0[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd1: begin
                  msg_buff[1] <= alphanumeric_1[7:0];
                  msg_buff[2] <= alphanumeric_1[15:8];
                  msg_buff[3] <= alphanumeric_1[23:16];
                  msg_buff[4] <= alphanumeric_1[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd2: begin
                  msg_buff[1] <= alphanumeric_2[7:0];
                  msg_buff[2] <= alphanumeric_2[15:8];
                  msg_buff[3] <= alphanumeric_2[23:16];
                  msg_buff[4] <= alphanumeric_2[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd3: begin
                  msg_buff[1] <= alphanumeric_3[7:0];
                  msg_buff[2] <= alphanumeric_3[15:8];
                  msg_buff[3] <= alphanumeric_3[23:16];
                  msg_buff[4] <= alphanumeric_3[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd4: begin
                  msg_buff[1] <= alphanumeric_4[7:0];
                  msg_buff[2] <= alphanumeric_4[15:8];
                  msg_buff[3] <= alphanumeric_4[23:16];
                  msg_buff[4] <= alphanumeric_4[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd5: begin
                  msg_buff[1] <= alphanumeric_5[7:0];
                  msg_buff[2] <= alphanumeric_5[15:8];
                  msg_buff[3] <= alphanumeric_5[23:16];
                  msg_buff[4] <= alphanumeric_5[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd6: begin
                  msg_buff[1] <= alphanumeric_6[7:0];
                  msg_buff[2] <= alphanumeric_6[15:8];
                  msg_buff[3] <= alphanumeric_6[23:16];
                  msg_buff[4] <= alphanumeric_6[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd7: begin
                  msg_buff[1] <= alphanumeric_7[7:0];
                  msg_buff[2] <= alphanumeric_7[15:8];
                  msg_buff[3] <= alphanumeric_7[23:16];
                  msg_buff[4] <= alphanumeric_7[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd8: begin
                  msg_buff[1] <= alphanumeric_8[7:0];
                  msg_buff[2] <= alphanumeric_8[15:8];
                  msg_buff[3] <= alphanumeric_8[23:16];
                  msg_buff[4] <= alphanumeric_8[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd9: begin
                  msg_buff[1] <= alphanumeric_9[7:0];
                  msg_buff[2] <= alphanumeric_9[15:8];
                  msg_buff[3] <= alphanumeric_9[23:16];
                  msg_buff[4] <= alphanumeric_9[31:24];
                  msg_buff[5] <= 8'd0;
                end
              endcase
            end
            4'd5: begin
              msg_buff[1] <= alphanumeric_dot[7:0];
              msg_buff[2] <= alphanumeric_dot[15:8];
              msg_buff[3] <= alphanumeric_dot[23:16];
              msg_buff[4] <= alphanumeric_dot[31:24];
              msg_buff[5] <= 8'd0;
            end
            4'd4: begin
              case(Digit[0])
                4'd0: begin
                  msg_buff[1] <= alphanumeric_0[7:0];
                  msg_buff[2] <= alphanumeric_0[15:8];
                  msg_buff[3] <= alphanumeric_0[23:16];
                  msg_buff[4] <= alphanumeric_0[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd1: begin
                  msg_buff[1] <= alphanumeric_1[7:0];
                  msg_buff[2] <= alphanumeric_1[15:8];
                  msg_buff[3] <= alphanumeric_1[23:16];
                  msg_buff[4] <= alphanumeric_1[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd2: begin
                  msg_buff[1] <= alphanumeric_2[7:0];
                  msg_buff[2] <= alphanumeric_2[15:8];
                  msg_buff[3] <= alphanumeric_2[23:16];
                  msg_buff[4] <= alphanumeric_2[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd3: begin
                  msg_buff[1] <= alphanumeric_3[7:0];
                  msg_buff[2] <= alphanumeric_3[15:8];
                  msg_buff[3] <= alphanumeric_3[23:16];
                  msg_buff[4] <= alphanumeric_3[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd4: begin
                  msg_buff[1] <= alphanumeric_4[7:0];
                  msg_buff[2] <= alphanumeric_4[15:8];
                  msg_buff[3] <= alphanumeric_4[23:16];
                  msg_buff[4] <= alphanumeric_4[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd5: begin
                  msg_buff[1] <= alphanumeric_5[7:0];
                  msg_buff[2] <= alphanumeric_5[15:8];
                  msg_buff[3] <= alphanumeric_5[23:16];
                  msg_buff[4] <= alphanumeric_5[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd6: begin
                  msg_buff[1] <= alphanumeric_6[7:0];
                  msg_buff[2] <= alphanumeric_6[15:8];
                  msg_buff[3] <= alphanumeric_6[23:16];
                  msg_buff[4] <= alphanumeric_6[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd7: begin
                  msg_buff[1] <= alphanumeric_7[7:0];
                  msg_buff[2] <= alphanumeric_7[15:8];
                  msg_buff[3] <= alphanumeric_7[23:16];
                  msg_buff[4] <= alphanumeric_7[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd8: begin
                  msg_buff[1] <= alphanumeric_8[7:0];
                  msg_buff[2] <= alphanumeric_8[15:8];
                  msg_buff[3] <= alphanumeric_8[23:16];
                  msg_buff[4] <= alphanumeric_8[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd9: begin
                  msg_buff[1] <= alphanumeric_9[7:0];
                  msg_buff[2] <= alphanumeric_9[15:8];
                  msg_buff[3] <= alphanumeric_9[23:16];
                  msg_buff[4] <= alphanumeric_9[31:24];
                  msg_buff[5] <= 8'd0;
                end
              endcase
            end
            4'd3, 4'd2: begin
              msg_buff[1] <= 8'd0;
              msg_buff[2] <= 8'd0;
              msg_buff[3] <= 8'd0;
              msg_buff[4] <= 8'd0;
              msg_buff[5] <= 8'd0;
            end
            4'd1: begin
              msg_buff[0] <= 8'd0;
              msg_buff[1] <= 8'd0;
              msg_buff[2] <= 8'd0;
              msg_buff[3] <= 8'd0;
              msg_buff[4] <= 8'd0;
            end
            4'd0: begin
              msg_buff[1] <= 8'b0010_0000;
              msg_buff[2] <= 8'b0100_0011;
              msg_buff[3] <= 8'b1001_1000;
            end
          endcase
        end
        TRIP_TIMER: begin
          case(letter_num)
            4'd7: begin
              case(Digit[2])
                4'd0: begin
                  msg_buff[1] <= alphanumeric_0[7:0];
                  msg_buff[2] <= alphanumeric_0[15:8];
                  msg_buff[3] <= alphanumeric_0[23:16];
                  msg_buff[4] <= alphanumeric_0[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd1: begin
                  msg_buff[1] <= alphanumeric_1[7:0];
                  msg_buff[2] <= alphanumeric_1[15:8];
                  msg_buff[3] <= alphanumeric_1[23:16];
                  msg_buff[4] <= alphanumeric_1[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd2: begin
                  msg_buff[1] <= alphanumeric_2[7:0];
                  msg_buff[2] <= alphanumeric_2[15:8];
                  msg_buff[3] <= alphanumeric_2[23:16];
                  msg_buff[4] <= alphanumeric_2[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd3: begin
                  msg_buff[1] <= alphanumeric_3[7:0];
                  msg_buff[2] <= alphanumeric_3[15:8];
                  msg_buff[3] <= alphanumeric_3[23:16];
                  msg_buff[4] <= alphanumeric_3[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd4: begin
                  msg_buff[1] <= alphanumeric_4[7:0];
                  msg_buff[2] <= alphanumeric_4[15:8];
                  msg_buff[3] <= alphanumeric_4[23:16];
                  msg_buff[4] <= alphanumeric_4[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd5: begin
                  msg_buff[1] <= alphanumeric_5[7:0];
                  msg_buff[2] <= alphanumeric_5[15:8];
                  msg_buff[3] <= alphanumeric_5[23:16];
                  msg_buff[4] <= alphanumeric_5[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd6: begin
                  msg_buff[1] <= alphanumeric_6[7:0];
                  msg_buff[2] <= alphanumeric_6[15:8];
                  msg_buff[3] <= alphanumeric_6[23:16];
                  msg_buff[4] <= alphanumeric_6[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd7: begin
                  msg_buff[1] <= alphanumeric_7[7:0];
                  msg_buff[2] <= alphanumeric_7[15:8];
                  msg_buff[3] <= alphanumeric_7[23:16];
                  msg_buff[4] <= alphanumeric_7[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd8: begin
                  msg_buff[1] <= alphanumeric_8[7:0];
                  msg_buff[2] <= alphanumeric_8[15:8];
                  msg_buff[3] <= alphanumeric_8[23:16];
                  msg_buff[4] <= alphanumeric_8[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd9: begin
                  msg_buff[1] <= alphanumeric_9[7:0];
                  msg_buff[2] <= alphanumeric_9[15:8];
                  msg_buff[3] <= alphanumeric_9[23:16];
                  msg_buff[4] <= alphanumeric_9[31:24];
                  msg_buff[5] <= 8'd0;
                end
              endcase
            end
            4'd6: begin
              msg_buff[1] <= alphanumeric_colon[7:0];
              msg_buff[2] <= alphanumeric_colon[15:8];
              msg_buff[3] <= alphanumeric_colon[23:16];
              msg_buff[4] <= alphanumeric_colon[31:24];
              msg_buff[5] <= 8'd0;
            end
            4'd5, 4'd4: begin
              case(Digit[letter_num-4'd4])
                4'd0: begin
                  msg_buff[1] <= alphanumeric_0[7:0];
                  msg_buff[2] <= alphanumeric_0[15:8];
                  msg_buff[3] <= alphanumeric_0[23:16];
                  msg_buff[4] <= alphanumeric_0[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd1: begin
                  msg_buff[1] <= alphanumeric_1[7:0];
                  msg_buff[2] <= alphanumeric_1[15:8];
                  msg_buff[3] <= alphanumeric_1[23:16];
                  msg_buff[4] <= alphanumeric_1[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd2: begin
                  msg_buff[1] <= alphanumeric_2[7:0];
                  msg_buff[2] <= alphanumeric_2[15:8];
                  msg_buff[3] <= alphanumeric_2[23:16];
                  msg_buff[4] <= alphanumeric_2[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd3: begin
                  msg_buff[1] <= alphanumeric_3[7:0];
                  msg_buff[2] <= alphanumeric_3[15:8];
                  msg_buff[3] <= alphanumeric_3[23:16];
                  msg_buff[4] <= alphanumeric_3[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd4: begin
                  msg_buff[1] <= alphanumeric_4[7:0];
                  msg_buff[2] <= alphanumeric_4[15:8];
                  msg_buff[3] <= alphanumeric_4[23:16];
                  msg_buff[4] <= alphanumeric_4[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd5: begin
                  msg_buff[1] <= alphanumeric_5[7:0];
                  msg_buff[2] <= alphanumeric_5[15:8];
                  msg_buff[3] <= alphanumeric_5[23:16];
                  msg_buff[4] <= alphanumeric_5[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd6: begin
                  msg_buff[1] <= alphanumeric_6[7:0];
                  msg_buff[2] <= alphanumeric_6[15:8];
                  msg_buff[3] <= alphanumeric_6[23:16];
                  msg_buff[4] <= alphanumeric_6[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd7: begin
                  msg_buff[1] <= alphanumeric_7[7:0];
                  msg_buff[2] <= alphanumeric_7[15:8];
                  msg_buff[3] <= alphanumeric_7[23:16];
                  msg_buff[4] <= alphanumeric_7[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd8: begin
                  msg_buff[1] <= alphanumeric_8[7:0];
                  msg_buff[2] <= alphanumeric_8[15:8];
                  msg_buff[3] <= alphanumeric_8[23:16];
                  msg_buff[4] <= alphanumeric_8[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd9: begin
                  msg_buff[1] <= alphanumeric_9[7:0];
                  msg_buff[2] <= alphanumeric_9[15:8];
                  msg_buff[3] <= alphanumeric_9[23:16];
                  msg_buff[4] <= alphanumeric_9[31:24];
                  msg_buff[5] <= 8'd0;
                end
              endcase
            end
            4'd3, 4'd2: begin
              msg_buff[1] <= 8'd0;
              msg_buff[2] <= 8'd0;
              msg_buff[3] <= 8'd0;
              msg_buff[4] <= 8'd0;
              msg_buff[5] <= 8'd0;
            end
            4'd1: begin
              msg_buff[0] <= 8'd0;
              msg_buff[1] <= 8'd0;
              msg_buff[2] <= 8'd0;
              msg_buff[3] <= 8'd0;
              msg_buff[4] <= 8'd0;
            end
            4'd0: begin
              msg_buff[1] <= 8'b0010_0000;
              msg_buff[2] <= 8'b0100_0011;
              msg_buff[3] <= 8'b1001_1000;
            end
          endcase
        end
        SPEEDOMETER: begin
          case(letter_num)
            4'd7: begin
              case(Digit[2])
                4'd0: begin
                  msg_buff[1] <= alphanumeric_0[7:0];
                  msg_buff[2] <= alphanumeric_0[15:8];
                  msg_buff[3] <= alphanumeric_0[23:16];
                  msg_buff[4] <= alphanumeric_0[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd1: begin
                  msg_buff[1] <= alphanumeric_1[7:0];
                  msg_buff[2] <= alphanumeric_1[15:8];
                  msg_buff[3] <= alphanumeric_1[23:16];
                  msg_buff[4] <= alphanumeric_1[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd2: begin
                  msg_buff[1] <= alphanumeric_2[7:0];
                  msg_buff[2] <= alphanumeric_2[15:8];
                  msg_buff[3] <= alphanumeric_2[23:16];
                  msg_buff[4] <= alphanumeric_2[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd3: begin
                  msg_buff[1] <= alphanumeric_3[7:0];
                  msg_buff[2] <= alphanumeric_3[15:8];
                  msg_buff[3] <= alphanumeric_3[23:16];
                  msg_buff[4] <= alphanumeric_3[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd4: begin
                  msg_buff[1] <= alphanumeric_4[7:0];
                  msg_buff[2] <= alphanumeric_4[15:8];
                  msg_buff[3] <= alphanumeric_4[23:16];
                  msg_buff[4] <= alphanumeric_4[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd5: begin
                  msg_buff[1] <= alphanumeric_5[7:0];
                  msg_buff[2] <= alphanumeric_5[15:8];
                  msg_buff[3] <= alphanumeric_5[23:16];
                  msg_buff[4] <= alphanumeric_5[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd6: begin
                  msg_buff[1] <= alphanumeric_6[7:0];
                  msg_buff[2] <= alphanumeric_6[15:8];
                  msg_buff[3] <= alphanumeric_6[23:16];
                  msg_buff[4] <= alphanumeric_6[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd7: begin
                  msg_buff[1] <= alphanumeric_7[7:0];
                  msg_buff[2] <= alphanumeric_7[15:8];
                  msg_buff[3] <= alphanumeric_7[23:16];
                  msg_buff[4] <= alphanumeric_7[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd8: begin
                  msg_buff[1] <= alphanumeric_8[7:0];
                  msg_buff[2] <= alphanumeric_8[15:8];
                  msg_buff[3] <= alphanumeric_8[23:16];
                  msg_buff[4] <= alphanumeric_8[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd9: begin
                  msg_buff[1] <= alphanumeric_9[7:0];
                  msg_buff[2] <= alphanumeric_9[15:8];
                  msg_buff[3] <= alphanumeric_9[23:16];
                  msg_buff[4] <= alphanumeric_9[31:24];
                  msg_buff[5] <= 8'd0;
                end
              endcase
            end
            4'd6: begin
              if(MemData < 16'd1_000) begin
                msg_buff[1] <= alphanumeric_dot[7:0];
                msg_buff[2] <= alphanumeric_dot[15:8];
                msg_buff[3] <= alphanumeric_dot[23:16];
                msg_buff[4] <= alphanumeric_dot[31:24];
                msg_buff[5] <= 8'd0;
              end
              else
                case(Digit[1])
                4'd0: begin
                  msg_buff[1] <= alphanumeric_0[7:0];
                  msg_buff[2] <= alphanumeric_0[15:8];
                  msg_buff[3] <= alphanumeric_0[23:16];
                  msg_buff[4] <= alphanumeric_0[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd1: begin
                  msg_buff[1] <= alphanumeric_1[7:0];
                  msg_buff[2] <= alphanumeric_1[15:8];
                  msg_buff[3] <= alphanumeric_1[23:16];
                  msg_buff[4] <= alphanumeric_1[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd2: begin
                  msg_buff[1] <= alphanumeric_2[7:0];
                  msg_buff[2] <= alphanumeric_2[15:8];
                  msg_buff[3] <= alphanumeric_2[23:16];
                  msg_buff[4] <= alphanumeric_2[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd3: begin
                  msg_buff[1] <= alphanumeric_3[7:0];
                  msg_buff[2] <= alphanumeric_3[15:8];
                  msg_buff[3] <= alphanumeric_3[23:16];
                  msg_buff[4] <= alphanumeric_3[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd4: begin
                  msg_buff[1] <= alphanumeric_4[7:0];
                  msg_buff[2] <= alphanumeric_4[15:8];
                  msg_buff[3] <= alphanumeric_4[23:16];
                  msg_buff[4] <= alphanumeric_4[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd5: begin
                  msg_buff[1] <= alphanumeric_5[7:0];
                  msg_buff[2] <= alphanumeric_5[15:8];
                  msg_buff[3] <= alphanumeric_5[23:16];
                  msg_buff[4] <= alphanumeric_5[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd6: begin
                  msg_buff[1] <= alphanumeric_6[7:0];
                  msg_buff[2] <= alphanumeric_6[15:8];
                  msg_buff[3] <= alphanumeric_6[23:16];
                  msg_buff[4] <= alphanumeric_6[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd7: begin
                  msg_buff[1] <= alphanumeric_7[7:0];
                  msg_buff[2] <= alphanumeric_7[15:8];
                  msg_buff[3] <= alphanumeric_7[23:16];
                  msg_buff[4] <= alphanumeric_7[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd8: begin
                  msg_buff[1] <= alphanumeric_8[7:0];
                  msg_buff[2] <= alphanumeric_8[15:8];
                  msg_buff[3] <= alphanumeric_8[23:16];
                  msg_buff[4] <= alphanumeric_8[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd9: begin
                  msg_buff[1] <= alphanumeric_9[7:0];
                  msg_buff[2] <= alphanumeric_9[15:8];
                  msg_buff[3] <= alphanumeric_9[23:16];
                  msg_buff[4] <= alphanumeric_9[31:24];
                  msg_buff[5] <= 8'd0;
                end
              endcase
            end
            4'd5: begin
              if(MemData < 16'd1_000)
                case(Digit[1])
                  4'd0: begin
                    msg_buff[1] <= alphanumeric_0[7:0];
                    msg_buff[2] <= alphanumeric_0[15:8];
                    msg_buff[3] <= alphanumeric_0[23:16];
                    msg_buff[4] <= alphanumeric_0[31:24];
                    msg_buff[5] <= 8'd0;
                  end
                  4'd1: begin
                    msg_buff[1] <= alphanumeric_1[7:0];
                    msg_buff[2] <= alphanumeric_1[15:8];
                    msg_buff[3] <= alphanumeric_1[23:16];
                    msg_buff[4] <= alphanumeric_1[31:24];
                    msg_buff[5] <= 8'd0;
                  end
                  4'd2: begin
                    msg_buff[1] <= alphanumeric_2[7:0];
                    msg_buff[2] <= alphanumeric_2[15:8];
                    msg_buff[3] <= alphanumeric_2[23:16];
                    msg_buff[4] <= alphanumeric_2[31:24];
                    msg_buff[5] <= 8'd0;
                  end
                  4'd3: begin
                    msg_buff[1] <= alphanumeric_3[7:0];
                    msg_buff[2] <= alphanumeric_3[15:8];
                    msg_buff[3] <= alphanumeric_3[23:16];
                    msg_buff[4] <= alphanumeric_3[31:24];
                    msg_buff[5] <= 8'd0;
                  end
                  4'd4: begin
                    msg_buff[1] <= alphanumeric_4[7:0];
                    msg_buff[2] <= alphanumeric_4[15:8];
                    msg_buff[3] <= alphanumeric_4[23:16];
                    msg_buff[4] <= alphanumeric_4[31:24];
                    msg_buff[5] <= 8'd0;
                  end
                  4'd5: begin
                    msg_buff[1] <= alphanumeric_5[7:0];
                    msg_buff[2] <= alphanumeric_5[15:8];
                    msg_buff[3] <= alphanumeric_5[23:16];
                    msg_buff[4] <= alphanumeric_5[31:24];
                    msg_buff[5] <= 8'd0;
                  end
                  4'd6: begin
                    msg_buff[1] <= alphanumeric_6[7:0];
                    msg_buff[2] <= alphanumeric_6[15:8];
                    msg_buff[3] <= alphanumeric_6[23:16];
                    msg_buff[4] <= alphanumeric_6[31:24];
                    msg_buff[5] <= 8'd0;
                  end
                  4'd7: begin
                    msg_buff[1] <= alphanumeric_7[7:0];
                    msg_buff[2] <= alphanumeric_7[15:8];
                    msg_buff[3] <= alphanumeric_7[23:16];
                    msg_buff[4] <= alphanumeric_7[31:24];
                    msg_buff[5] <= 8'd0;
                  end
                  4'd8: begin
                    msg_buff[1] <= alphanumeric_8[7:0];
                    msg_buff[2] <= alphanumeric_8[15:8];
                    msg_buff[3] <= alphanumeric_8[23:16];
                    msg_buff[4] <= alphanumeric_8[31:24];
                    msg_buff[5] <= 8'd0;
                  end
                  4'd9: begin
                    msg_buff[1] <= alphanumeric_9[7:0];
                    msg_buff[2] <= alphanumeric_9[15:8];
                    msg_buff[3] <= alphanumeric_9[23:16];
                    msg_buff[4] <= alphanumeric_9[31:24];
                    msg_buff[5] <= 8'd0;
                  end
                endcase
              else begin
                msg_buff[1] <= alphanumeric_dot[7:0];
                msg_buff[2] <= alphanumeric_dot[15:8];
                msg_buff[3] <= alphanumeric_dot[23:16];
                msg_buff[4] <= alphanumeric_dot[31:24];
                msg_buff[5] <= 8'd0;
              end
            end
            4'd4: begin
              case(Digit[0])
                4'd0: begin
                  msg_buff[1] <= alphanumeric_0[7:0];
                  msg_buff[2] <= alphanumeric_0[15:8];
                  msg_buff[3] <= alphanumeric_0[23:16];
                  msg_buff[4] <= alphanumeric_0[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd1: begin
                  msg_buff[1] <= alphanumeric_1[7:0];
                  msg_buff[2] <= alphanumeric_1[15:8];
                  msg_buff[3] <= alphanumeric_1[23:16];
                  msg_buff[4] <= alphanumeric_1[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd2: begin
                  msg_buff[1] <= alphanumeric_2[7:0];
                  msg_buff[2] <= alphanumeric_2[15:8];
                  msg_buff[3] <= alphanumeric_2[23:16];
                  msg_buff[4] <= alphanumeric_2[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd3: begin
                  msg_buff[1] <= alphanumeric_3[7:0];
                  msg_buff[2] <= alphanumeric_3[15:8];
                  msg_buff[3] <= alphanumeric_3[23:16];
                  msg_buff[4] <= alphanumeric_3[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd4: begin
                  msg_buff[1] <= alphanumeric_4[7:0];
                  msg_buff[2] <= alphanumeric_4[15:8];
                  msg_buff[3] <= alphanumeric_4[23:16];
                  msg_buff[4] <= alphanumeric_4[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd5: begin
                  msg_buff[1] <= alphanumeric_5[7:0];
                  msg_buff[2] <= alphanumeric_5[15:8];
                  msg_buff[3] <= alphanumeric_5[23:16];
                  msg_buff[4] <= alphanumeric_5[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd6: begin
                  msg_buff[1] <= alphanumeric_6[7:0];
                  msg_buff[2] <= alphanumeric_6[15:8];
                  msg_buff[3] <= alphanumeric_6[23:16];
                  msg_buff[4] <= alphanumeric_6[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd7: begin
                  msg_buff[1] <= alphanumeric_7[7:0];
                  msg_buff[2] <= alphanumeric_7[15:8];
                  msg_buff[3] <= alphanumeric_7[23:16];
                  msg_buff[4] <= alphanumeric_7[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd8: begin
                  msg_buff[1] <= alphanumeric_8[7:0];
                  msg_buff[2] <= alphanumeric_8[15:8];
                  msg_buff[3] <= alphanumeric_8[23:16];
                  msg_buff[4] <= alphanumeric_8[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd9: begin
                  msg_buff[1] <= alphanumeric_9[7:0];
                  msg_buff[2] <= alphanumeric_9[15:8];
                  msg_buff[3] <= alphanumeric_9[23:16];
                  msg_buff[4] <= alphanumeric_9[31:24];
                  msg_buff[5] <= 8'd0;
                end
              endcase
            end
            4'd3, 4'd2: begin
              msg_buff[1] <= 8'd0;
              msg_buff[2] <= 8'd0;
              msg_buff[3] <= 8'd0;
              msg_buff[4] <= 8'd0;
              msg_buff[5] <= 8'd0;
            end
            4'd1: begin
              msg_buff[0] <= 8'd0;
              msg_buff[1] <= 8'd0;
              msg_buff[2] <= 8'd0;
              msg_buff[3] <= 8'd0;
              msg_buff[4] <= 8'd0;
            end
            4'd0: begin
              msg_buff[1] <= 8'b0010_0000;
              msg_buff[2] <= 8'b0100_0011;
              msg_buff[3] <= 8'b1001_1000;
            end
          endcase
        end
        CADENCE: begin
          case(letter_num)
            4'd7, 4'd6: begin
              case(Digit[letter_num-4'd5])
                4'd0: begin
                  msg_buff[1] <= alphanumeric_0[7:0];
                  msg_buff[2] <= alphanumeric_0[15:8];
                  msg_buff[3] <= alphanumeric_0[23:16];
                  msg_buff[4] <= alphanumeric_0[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd1: begin
                  msg_buff[1] <= alphanumeric_1[7:0];
                  msg_buff[2] <= alphanumeric_1[15:8];
                  msg_buff[3] <= alphanumeric_1[23:16];
                  msg_buff[4] <= alphanumeric_1[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd2: begin
                  msg_buff[1] <= alphanumeric_2[7:0];
                  msg_buff[2] <= alphanumeric_2[15:8];
                  msg_buff[3] <= alphanumeric_2[23:16];
                  msg_buff[4] <= alphanumeric_2[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd3: begin
                  msg_buff[1] <= alphanumeric_3[7:0];
                  msg_buff[2] <= alphanumeric_3[15:8];
                  msg_buff[3] <= alphanumeric_3[23:16];
                  msg_buff[4] <= alphanumeric_3[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd4: begin
                  msg_buff[1] <= alphanumeric_4[7:0];
                  msg_buff[2] <= alphanumeric_4[15:8];
                  msg_buff[3] <= alphanumeric_4[23:16];
                  msg_buff[4] <= alphanumeric_4[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd5: begin
                  msg_buff[1] <= alphanumeric_5[7:0];
                  msg_buff[2] <= alphanumeric_5[15:8];
                  msg_buff[3] <= alphanumeric_5[23:16];
                  msg_buff[4] <= alphanumeric_5[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd6: begin
                  msg_buff[1] <= alphanumeric_6[7:0];
                  msg_buff[2] <= alphanumeric_6[15:8];
                  msg_buff[3] <= alphanumeric_6[23:16];
                  msg_buff[4] <= alphanumeric_6[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd7: begin
                  msg_buff[1] <= alphanumeric_7[7:0];
                  msg_buff[2] <= alphanumeric_7[15:8];
                  msg_buff[3] <= alphanumeric_7[23:16];
                  msg_buff[4] <= alphanumeric_7[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd8: begin
                  msg_buff[1] <= alphanumeric_8[7:0];
                  msg_buff[2] <= alphanumeric_8[15:8];
                  msg_buff[3] <= alphanumeric_8[23:16];
                  msg_buff[4] <= alphanumeric_8[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd9: begin
                  msg_buff[1] <= alphanumeric_9[7:0];
                  msg_buff[2] <= alphanumeric_9[15:8];
                  msg_buff[3] <= alphanumeric_9[23:16];
                  msg_buff[4] <= alphanumeric_9[31:24];
                  msg_buff[5] <= 8'd0;
                end
              endcase
            end
            4'd5: begin
              if (MemData < 16'd10_000) begin
                msg_buff[1] <= alphanumeric_dot[7:0];
                msg_buff[2] <= alphanumeric_dot[15:8];
                msg_buff[3] <= alphanumeric_dot[23:16];
                msg_buff[4] <= alphanumeric_dot[31:24];
                msg_buff[5] <= 8'd0;
              end
              else
                case(Digit[0])
                4'd0: begin
                  msg_buff[1] <= alphanumeric_0[7:0];
                  msg_buff[2] <= alphanumeric_0[15:8];
                  msg_buff[3] <= alphanumeric_0[23:16];
                  msg_buff[4] <= alphanumeric_0[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd1: begin
                  msg_buff[1] <= alphanumeric_1[7:0];
                  msg_buff[2] <= alphanumeric_1[15:8];
                  msg_buff[3] <= alphanumeric_1[23:16];
                  msg_buff[4] <= alphanumeric_1[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd2: begin
                  msg_buff[1] <= alphanumeric_2[7:0];
                  msg_buff[2] <= alphanumeric_2[15:8];
                  msg_buff[3] <= alphanumeric_2[23:16];
                  msg_buff[4] <= alphanumeric_2[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd3: begin
                  msg_buff[1] <= alphanumeric_3[7:0];
                  msg_buff[2] <= alphanumeric_3[15:8];
                  msg_buff[3] <= alphanumeric_3[23:16];
                  msg_buff[4] <= alphanumeric_3[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd4: begin
                  msg_buff[1] <= alphanumeric_4[7:0];
                  msg_buff[2] <= alphanumeric_4[15:8];
                  msg_buff[3] <= alphanumeric_4[23:16];
                  msg_buff[4] <= alphanumeric_4[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd5: begin
                  msg_buff[1] <= alphanumeric_5[7:0];
                  msg_buff[2] <= alphanumeric_5[15:8];
                  msg_buff[3] <= alphanumeric_5[23:16];
                  msg_buff[4] <= alphanumeric_5[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd6: begin
                  msg_buff[1] <= alphanumeric_6[7:0];
                  msg_buff[2] <= alphanumeric_6[15:8];
                  msg_buff[3] <= alphanumeric_6[23:16];
                  msg_buff[4] <= alphanumeric_6[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd7: begin
                  msg_buff[1] <= alphanumeric_7[7:0];
                  msg_buff[2] <= alphanumeric_7[15:8];
                  msg_buff[3] <= alphanumeric_7[23:16];
                  msg_buff[4] <= alphanumeric_7[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd8: begin
                  msg_buff[1] <= alphanumeric_8[7:0];
                  msg_buff[2] <= alphanumeric_8[15:8];
                  msg_buff[3] <= alphanumeric_8[23:16];
                  msg_buff[4] <= alphanumeric_8[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd9: begin
                  msg_buff[1] <= alphanumeric_9[7:0];
                  msg_buff[2] <= alphanumeric_9[15:8];
                  msg_buff[3] <= alphanumeric_9[23:16];
                  msg_buff[4] <= alphanumeric_9[31:24];
                  msg_buff[5] <= 8'd0;
                end
              endcase
            end
            4'd4: begin
              if (MemData < 16'd10_000)
                case(Digit[0])
                  4'd0: begin
                    msg_buff[1] <= alphanumeric_0[7:0];
                    msg_buff[2] <= alphanumeric_0[15:8];
                    msg_buff[3] <= alphanumeric_0[23:16];
                    msg_buff[4] <= alphanumeric_0[31:24];
                    msg_buff[5] <= 8'd0;
                  end
                  4'd1: begin
                    msg_buff[1] <= alphanumeric_1[7:0];
                    msg_buff[2] <= alphanumeric_1[15:8];
                    msg_buff[3] <= alphanumeric_1[23:16];
                    msg_buff[4] <= alphanumeric_1[31:24];
                    msg_buff[5] <= 8'd0;
                  end
                  4'd2: begin
                    msg_buff[1] <= alphanumeric_2[7:0];
                    msg_buff[2] <= alphanumeric_2[15:8];
                    msg_buff[3] <= alphanumeric_2[23:16];
                    msg_buff[4] <= alphanumeric_2[31:24];
                    msg_buff[5] <= 8'd0;
                  end
                  4'd3: begin
                    msg_buff[1] <= alphanumeric_3[7:0];
                    msg_buff[2] <= alphanumeric_3[15:8];
                    msg_buff[3] <= alphanumeric_3[23:16];
                    msg_buff[4] <= alphanumeric_3[31:24];
                    msg_buff[5] <= 8'd0;
                  end
                  4'd4: begin
                    msg_buff[1] <= alphanumeric_4[7:0];
                    msg_buff[2] <= alphanumeric_4[15:8];
                    msg_buff[3] <= alphanumeric_4[23:16];
                    msg_buff[4] <= alphanumeric_4[31:24];
                    msg_buff[5] <= 8'd0;
                  end
                  4'd5: begin
                    msg_buff[1] <= alphanumeric_5[7:0];
                    msg_buff[2] <= alphanumeric_5[15:8];
                    msg_buff[3] <= alphanumeric_5[23:16];
                    msg_buff[4] <= alphanumeric_5[31:24];
                    msg_buff[5] <= 8'd0;
                  end
                  4'd6: begin
                    msg_buff[1] <= alphanumeric_6[7:0];
                    msg_buff[2] <= alphanumeric_6[15:8];
                    msg_buff[3] <= alphanumeric_6[23:16];
                    msg_buff[4] <= alphanumeric_6[31:24];
                    msg_buff[5] <= 8'd0;
                  end
                  4'd7: begin
                    msg_buff[1] <= alphanumeric_7[7:0];
                    msg_buff[2] <= alphanumeric_7[15:8];
                    msg_buff[3] <= alphanumeric_7[23:16];
                    msg_buff[4] <= alphanumeric_7[31:24];
                    msg_buff[5] <= 8'd0;
                  end
                  4'd8: begin
                    msg_buff[1] <= alphanumeric_8[7:0];
                    msg_buff[2] <= alphanumeric_8[15:8];
                    msg_buff[3] <= alphanumeric_8[23:16];
                    msg_buff[4] <= alphanumeric_8[31:24];
                    msg_buff[5] <= 8'd0;
                  end
                  4'd9: begin
                    msg_buff[1] <= alphanumeric_9[7:0];
                    msg_buff[2] <= alphanumeric_9[15:8];
                    msg_buff[3] <= alphanumeric_9[23:16];
                    msg_buff[4] <= alphanumeric_9[31:24];
                    msg_buff[5] <= 8'd0;
                  end
                endcase
              else begin
                msg_buff[1] <= 8'd0;
                msg_buff[2] <= 8'd0;
                msg_buff[3] <= 8'd0;
                msg_buff[4] <= 8'd0;
                msg_buff[5] <= 8'd0;
              end
            end
            4'd3, 4'd2: begin
              msg_buff[1] <= 8'd0;
              msg_buff[2] <= 8'd0;
              msg_buff[3] <= 8'd0;
              msg_buff[4] <= 8'd0;
              msg_buff[5] <= 8'd0;
            end
            4'd1: begin
              msg_buff[0] <= 8'd0;
              msg_buff[1] <= 8'd0;
              msg_buff[2] <= 8'd0;
              msg_buff[3] <= 8'd0;
              msg_buff[4] <= 8'd0;
            end
            4'd0: begin
              msg_buff[1] <= 8'b0010_0000;
              msg_buff[2] <= 8'b0100_0011;
              msg_buff[3] <= 8'b1001_1000;
            end
          endcase
        end
        AVE_SPEED: begin
         case(letter_num)
            4'd7: begin
              case(Digit[2])
                4'd0: begin
                  msg_buff[1] <= alphanumeric_0[7:0];
                  msg_buff[2] <= alphanumeric_0[15:8];
                  msg_buff[3] <= alphanumeric_0[23:16];
                  msg_buff[4] <= alphanumeric_0[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd1: begin
                  msg_buff[1] <= alphanumeric_1[7:0];
                  msg_buff[2] <= alphanumeric_1[15:8];
                  msg_buff[3] <= alphanumeric_1[23:16];
                  msg_buff[4] <= alphanumeric_1[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd2: begin
                  msg_buff[1] <= alphanumeric_2[7:0];
                  msg_buff[2] <= alphanumeric_2[15:8];
                  msg_buff[3] <= alphanumeric_2[23:16];
                  msg_buff[4] <= alphanumeric_2[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd3: begin
                  msg_buff[1] <= alphanumeric_3[7:0];
                  msg_buff[2] <= alphanumeric_3[15:8];
                  msg_buff[3] <= alphanumeric_3[23:16];
                  msg_buff[4] <= alphanumeric_3[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd4: begin
                  msg_buff[1] <= alphanumeric_4[7:0];
                  msg_buff[2] <= alphanumeric_4[15:8];
                  msg_buff[3] <= alphanumeric_4[23:16];
                  msg_buff[4] <= alphanumeric_4[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd5: begin
                  msg_buff[1] <= alphanumeric_5[7:0];
                  msg_buff[2] <= alphanumeric_5[15:8];
                  msg_buff[3] <= alphanumeric_5[23:16];
                  msg_buff[4] <= alphanumeric_5[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd6: begin
                  msg_buff[1] <= alphanumeric_6[7:0];
                  msg_buff[2] <= alphanumeric_6[15:8];
                  msg_buff[3] <= alphanumeric_6[23:16];
                  msg_buff[4] <= alphanumeric_6[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd7: begin
                  msg_buff[1] <= alphanumeric_7[7:0];
                  msg_buff[2] <= alphanumeric_7[15:8];
                  msg_buff[3] <= alphanumeric_7[23:16];
                  msg_buff[4] <= alphanumeric_7[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd8: begin
                  msg_buff[1] <= alphanumeric_8[7:0];
                  msg_buff[2] <= alphanumeric_8[15:8];
                  msg_buff[3] <= alphanumeric_8[23:16];
                  msg_buff[4] <= alphanumeric_8[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd9: begin
                  msg_buff[1] <= alphanumeric_9[7:0];
                  msg_buff[2] <= alphanumeric_9[15:8];
                  msg_buff[3] <= alphanumeric_9[23:16];
                  msg_buff[4] <= alphanumeric_9[31:24];
                  msg_buff[5] <= 8'd0;
                end
              endcase
            end
            4'd6: begin
              if(MemData < 16'd1_000) begin
                msg_buff[1] <= alphanumeric_dot[7:0];
                msg_buff[2] <= alphanumeric_dot[15:8];
                msg_buff[3] <= alphanumeric_dot[23:16];
                msg_buff[4] <= alphanumeric_dot[31:24];
                msg_buff[5] <= 8'd0;
              end
              else
                case(Digit[1])
                4'd0: begin
                  msg_buff[1] <= alphanumeric_0[7:0];
                  msg_buff[2] <= alphanumeric_0[15:8];
                  msg_buff[3] <= alphanumeric_0[23:16];
                  msg_buff[4] <= alphanumeric_0[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd1: begin
                  msg_buff[1] <= alphanumeric_1[7:0];
                  msg_buff[2] <= alphanumeric_1[15:8];
                  msg_buff[3] <= alphanumeric_1[23:16];
                  msg_buff[4] <= alphanumeric_1[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd2: begin
                  msg_buff[1] <= alphanumeric_2[7:0];
                  msg_buff[2] <= alphanumeric_2[15:8];
                  msg_buff[3] <= alphanumeric_2[23:16];
                  msg_buff[4] <= alphanumeric_2[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd3: begin
                  msg_buff[1] <= alphanumeric_3[7:0];
                  msg_buff[2] <= alphanumeric_3[15:8];
                  msg_buff[3] <= alphanumeric_3[23:16];
                  msg_buff[4] <= alphanumeric_3[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd4: begin
                  msg_buff[1] <= alphanumeric_4[7:0];
                  msg_buff[2] <= alphanumeric_4[15:8];
                  msg_buff[3] <= alphanumeric_4[23:16];
                  msg_buff[4] <= alphanumeric_4[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd5: begin
                  msg_buff[1] <= alphanumeric_5[7:0];
                  msg_buff[2] <= alphanumeric_5[15:8];
                  msg_buff[3] <= alphanumeric_5[23:16];
                  msg_buff[4] <= alphanumeric_5[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd6: begin
                  msg_buff[1] <= alphanumeric_6[7:0];
                  msg_buff[2] <= alphanumeric_6[15:8];
                  msg_buff[3] <= alphanumeric_6[23:16];
                  msg_buff[4] <= alphanumeric_6[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd7: begin
                  msg_buff[1] <= alphanumeric_7[7:0];
                  msg_buff[2] <= alphanumeric_7[15:8];
                  msg_buff[3] <= alphanumeric_7[23:16];
                  msg_buff[4] <= alphanumeric_7[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd8: begin
                  msg_buff[1] <= alphanumeric_8[7:0];
                  msg_buff[2] <= alphanumeric_8[15:8];
                  msg_buff[3] <= alphanumeric_8[23:16];
                  msg_buff[4] <= alphanumeric_8[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd9: begin
                  msg_buff[1] <= alphanumeric_9[7:0];
                  msg_buff[2] <= alphanumeric_9[15:8];
                  msg_buff[3] <= alphanumeric_9[23:16];
                  msg_buff[4] <= alphanumeric_9[31:24];
                  msg_buff[5] <= 8'd0;
                end
              endcase
            end
            4'd5: begin
              if(MemData < 16'd1_000)
                case(Digit[1])
                  4'd0: begin
                    msg_buff[1] <= alphanumeric_0[7:0];
                    msg_buff[2] <= alphanumeric_0[15:8];
                    msg_buff[3] <= alphanumeric_0[23:16];
                    msg_buff[4] <= alphanumeric_0[31:24];
                    msg_buff[5] <= 8'd0;
                  end
                  4'd1: begin
                    msg_buff[1] <= alphanumeric_1[7:0];
                    msg_buff[2] <= alphanumeric_1[15:8];
                    msg_buff[3] <= alphanumeric_1[23:16];
                    msg_buff[4] <= alphanumeric_1[31:24];
                    msg_buff[5] <= 8'd0;
                  end
                  4'd2: begin
                    msg_buff[1] <= alphanumeric_2[7:0];
                    msg_buff[2] <= alphanumeric_2[15:8];
                    msg_buff[3] <= alphanumeric_2[23:16];
                    msg_buff[4] <= alphanumeric_2[31:24];
                    msg_buff[5] <= 8'd0;
                  end
                  4'd3: begin
                    msg_buff[1] <= alphanumeric_3[7:0];
                    msg_buff[2] <= alphanumeric_3[15:8];
                    msg_buff[3] <= alphanumeric_3[23:16];
                    msg_buff[4] <= alphanumeric_3[31:24];
                    msg_buff[5] <= 8'd0;
                  end
                  4'd4: begin
                    msg_buff[1] <= alphanumeric_4[7:0];
                    msg_buff[2] <= alphanumeric_4[15:8];
                    msg_buff[3] <= alphanumeric_4[23:16];
                    msg_buff[4] <= alphanumeric_4[31:24];
                    msg_buff[5] <= 8'd0;
                  end
                  4'd5: begin
                    msg_buff[1] <= alphanumeric_5[7:0];
                    msg_buff[2] <= alphanumeric_5[15:8];
                    msg_buff[3] <= alphanumeric_5[23:16];
                    msg_buff[4] <= alphanumeric_5[31:24];
                    msg_buff[5] <= 8'd0;
                  end
                  4'd6: begin
                    msg_buff[1] <= alphanumeric_6[7:0];
                    msg_buff[2] <= alphanumeric_6[15:8];
                    msg_buff[3] <= alphanumeric_6[23:16];
                    msg_buff[4] <= alphanumeric_6[31:24];
                    msg_buff[5] <= 8'd0;
                  end
                  4'd7: begin
                    msg_buff[1] <= alphanumeric_7[7:0];
                    msg_buff[2] <= alphanumeric_7[15:8];
                    msg_buff[3] <= alphanumeric_7[23:16];
                    msg_buff[4] <= alphanumeric_7[31:24];
                    msg_buff[5] <= 8'd0;
                  end
                  4'd8: begin
                    msg_buff[1] <= alphanumeric_8[7:0];
                    msg_buff[2] <= alphanumeric_8[15:8];
                    msg_buff[3] <= alphanumeric_8[23:16];
                    msg_buff[4] <= alphanumeric_8[31:24];
                    msg_buff[5] <= 8'd0;
                  end
                  4'd9: begin
                    msg_buff[1] <= alphanumeric_9[7:0];
                    msg_buff[2] <= alphanumeric_9[15:8];
                    msg_buff[3] <= alphanumeric_9[23:16];
                    msg_buff[4] <= alphanumeric_9[31:24];
                    msg_buff[5] <= 8'd0;
                  end
                endcase
              else begin
                msg_buff[1] <= alphanumeric_dot[7:0];
                msg_buff[2] <= alphanumeric_dot[15:8];
                msg_buff[3] <= alphanumeric_dot[23:16];
                msg_buff[4] <= alphanumeric_dot[31:24];
                msg_buff[5] <= 8'd0;
              end
            end
            4'd4: begin
              case(Digit[0])
                4'd0: begin
                  msg_buff[1] <= alphanumeric_0[7:0];
                  msg_buff[2] <= alphanumeric_0[15:8];
                  msg_buff[3] <= alphanumeric_0[23:16];
                  msg_buff[4] <= alphanumeric_0[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd1: begin
                  msg_buff[1] <= alphanumeric_1[7:0];
                  msg_buff[2] <= alphanumeric_1[15:8];
                  msg_buff[3] <= alphanumeric_1[23:16];
                  msg_buff[4] <= alphanumeric_1[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd2: begin
                  msg_buff[1] <= alphanumeric_2[7:0];
                  msg_buff[2] <= alphanumeric_2[15:8];
                  msg_buff[3] <= alphanumeric_2[23:16];
                  msg_buff[4] <= alphanumeric_2[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd3: begin
                  msg_buff[1] <= alphanumeric_3[7:0];
                  msg_buff[2] <= alphanumeric_3[15:8];
                  msg_buff[3] <= alphanumeric_3[23:16];
                  msg_buff[4] <= alphanumeric_3[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd4: begin
                  msg_buff[1] <= alphanumeric_4[7:0];
                  msg_buff[2] <= alphanumeric_4[15:8];
                  msg_buff[3] <= alphanumeric_4[23:16];
                  msg_buff[4] <= alphanumeric_4[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd5: begin
                  msg_buff[1] <= alphanumeric_5[7:0];
                  msg_buff[2] <= alphanumeric_5[15:8];
                  msg_buff[3] <= alphanumeric_5[23:16];
                  msg_buff[4] <= alphanumeric_5[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd6: begin
                  msg_buff[1] <= alphanumeric_6[7:0];
                  msg_buff[2] <= alphanumeric_6[15:8];
                  msg_buff[3] <= alphanumeric_6[23:16];
                  msg_buff[4] <= alphanumeric_6[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd7: begin
                  msg_buff[1] <= alphanumeric_7[7:0];
                  msg_buff[2] <= alphanumeric_7[15:8];
                  msg_buff[3] <= alphanumeric_7[23:16];
                  msg_buff[4] <= alphanumeric_7[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd8: begin
                  msg_buff[1] <= alphanumeric_8[7:0];
                  msg_buff[2] <= alphanumeric_8[15:8];
                  msg_buff[3] <= alphanumeric_8[23:16];
                  msg_buff[4] <= alphanumeric_8[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd9: begin
                  msg_buff[1] <= alphanumeric_9[7:0];
                  msg_buff[2] <= alphanumeric_9[15:8];
                  msg_buff[3] <= alphanumeric_9[23:16];
                  msg_buff[4] <= alphanumeric_9[31:24];
                  msg_buff[5] <= 8'd0;
                end
              endcase
            end
            4'd3, 4'd2: begin
              msg_buff[1] <= 8'd0;
              msg_buff[2] <= 8'd0;
              msg_buff[3] <= 8'd0;
              msg_buff[4] <= 8'd0;
              msg_buff[5] <= 8'd0;
            end
            4'd1: begin
              msg_buff[0] <= 8'd0;
              msg_buff[1] <= 8'd0;
              msg_buff[2] <= 8'd0;
              msg_buff[3] <= 8'd0;
              msg_buff[4] <= 8'd0;
            end
            4'd0: begin
              msg_buff[1] <= 8'b0010_0000;
              msg_buff[2] <= 8'b0100_0011;
              msg_buff[3] <= 8'b1001_1000;
            end
          endcase
        end
        CALORIES: begin
           case(letter_num)
            4'd7, 4'd6: begin
              case(Digit[letter_num-4'd5])
                4'd0: begin
                  msg_buff[1] <= alphanumeric_0[7:0];
                  msg_buff[2] <= alphanumeric_0[15:8];
                  msg_buff[3] <= alphanumeric_0[23:16];
                  msg_buff[4] <= alphanumeric_0[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd1: begin
                  msg_buff[1] <= alphanumeric_1[7:0];
                  msg_buff[2] <= alphanumeric_1[15:8];
                  msg_buff[3] <= alphanumeric_1[23:16];
                  msg_buff[4] <= alphanumeric_1[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd2: begin
                  msg_buff[1] <= alphanumeric_2[7:0];
                  msg_buff[2] <= alphanumeric_2[15:8];
                  msg_buff[3] <= alphanumeric_2[23:16];
                  msg_buff[4] <= alphanumeric_2[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd3: begin
                  msg_buff[1] <= alphanumeric_3[7:0];
                  msg_buff[2] <= alphanumeric_3[15:8];
                  msg_buff[3] <= alphanumeric_3[23:16];
                  msg_buff[4] <= alphanumeric_3[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd4: begin
                  msg_buff[1] <= alphanumeric_4[7:0];
                  msg_buff[2] <= alphanumeric_4[15:8];
                  msg_buff[3] <= alphanumeric_4[23:16];
                  msg_buff[4] <= alphanumeric_4[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd5: begin
                  msg_buff[1] <= alphanumeric_5[7:0];
                  msg_buff[2] <= alphanumeric_5[15:8];
                  msg_buff[3] <= alphanumeric_5[23:16];
                  msg_buff[4] <= alphanumeric_5[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd6: begin
                  msg_buff[1] <= alphanumeric_6[7:0];
                  msg_buff[2] <= alphanumeric_6[15:8];
                  msg_buff[3] <= alphanumeric_6[23:16];
                  msg_buff[4] <= alphanumeric_6[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd7: begin
                  msg_buff[1] <= alphanumeric_7[7:0];
                  msg_buff[2] <= alphanumeric_7[15:8];
                  msg_buff[3] <= alphanumeric_7[23:16];
                  msg_buff[4] <= alphanumeric_7[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd8: begin
                  msg_buff[1] <= alphanumeric_8[7:0];
                  msg_buff[2] <= alphanumeric_8[15:8];
                  msg_buff[3] <= alphanumeric_8[23:16];
                  msg_buff[4] <= alphanumeric_8[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd9: begin
                  msg_buff[1] <= alphanumeric_9[7:0];
                  msg_buff[2] <= alphanumeric_9[15:8];
                  msg_buff[3] <= alphanumeric_9[23:16];
                  msg_buff[4] <= alphanumeric_9[31:24];
                  msg_buff[5] <= 8'd0;
                end
              endcase
            end
            4'd5: begin
              if (MemData < 16'd10_000) begin
                msg_buff[1] <= alphanumeric_dot[7:0];
                msg_buff[2] <= alphanumeric_dot[15:8];
                msg_buff[3] <= alphanumeric_dot[23:16];
                msg_buff[4] <= alphanumeric_dot[31:24];
                msg_buff[5] <= 8'd0;
              end
              else
                case(Digit[0])
                4'd0: begin
                  msg_buff[1] <= alphanumeric_0[7:0];
                  msg_buff[2] <= alphanumeric_0[15:8];
                  msg_buff[3] <= alphanumeric_0[23:16];
                  msg_buff[4] <= alphanumeric_0[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd1: begin
                  msg_buff[1] <= alphanumeric_1[7:0];
                  msg_buff[2] <= alphanumeric_1[15:8];
                  msg_buff[3] <= alphanumeric_1[23:16];
                  msg_buff[4] <= alphanumeric_1[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd2: begin
                  msg_buff[1] <= alphanumeric_2[7:0];
                  msg_buff[2] <= alphanumeric_2[15:8];
                  msg_buff[3] <= alphanumeric_2[23:16];
                  msg_buff[4] <= alphanumeric_2[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd3: begin
                  msg_buff[1] <= alphanumeric_3[7:0];
                  msg_buff[2] <= alphanumeric_3[15:8];
                  msg_buff[3] <= alphanumeric_3[23:16];
                  msg_buff[4] <= alphanumeric_3[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd4: begin
                  msg_buff[1] <= alphanumeric_4[7:0];
                  msg_buff[2] <= alphanumeric_4[15:8];
                  msg_buff[3] <= alphanumeric_4[23:16];
                  msg_buff[4] <= alphanumeric_4[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd5: begin
                  msg_buff[1] <= alphanumeric_5[7:0];
                  msg_buff[2] <= alphanumeric_5[15:8];
                  msg_buff[3] <= alphanumeric_5[23:16];
                  msg_buff[4] <= alphanumeric_5[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd6: begin
                  msg_buff[1] <= alphanumeric_6[7:0];
                  msg_buff[2] <= alphanumeric_6[15:8];
                  msg_buff[3] <= alphanumeric_6[23:16];
                  msg_buff[4] <= alphanumeric_6[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd7: begin
                  msg_buff[1] <= alphanumeric_7[7:0];
                  msg_buff[2] <= alphanumeric_7[15:8];
                  msg_buff[3] <= alphanumeric_7[23:16];
                  msg_buff[4] <= alphanumeric_7[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd8: begin
                  msg_buff[1] <= alphanumeric_8[7:0];
                  msg_buff[2] <= alphanumeric_8[15:8];
                  msg_buff[3] <= alphanumeric_8[23:16];
                  msg_buff[4] <= alphanumeric_8[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd9: begin
                  msg_buff[1] <= alphanumeric_9[7:0];
                  msg_buff[2] <= alphanumeric_9[15:8];
                  msg_buff[3] <= alphanumeric_9[23:16];
                  msg_buff[4] <= alphanumeric_9[31:24];
                  msg_buff[5] <= 8'd0;
                end
              endcase
            end
            4'd4: begin
              if (MemData < 16'd10_000)
                case(Digit[0])
                  4'd0: begin
                    msg_buff[1] <= alphanumeric_0[7:0];
                    msg_buff[2] <= alphanumeric_0[15:8];
                    msg_buff[3] <= alphanumeric_0[23:16];
                    msg_buff[4] <= alphanumeric_0[31:24];
                    msg_buff[5] <= 8'd0;
                  end
                  4'd1: begin
                    msg_buff[1] <= alphanumeric_1[7:0];
                    msg_buff[2] <= alphanumeric_1[15:8];
                    msg_buff[3] <= alphanumeric_1[23:16];
                    msg_buff[4] <= alphanumeric_1[31:24];
                    msg_buff[5] <= 8'd0;
                  end
                  4'd2: begin
                    msg_buff[1] <= alphanumeric_2[7:0];
                    msg_buff[2] <= alphanumeric_2[15:8];
                    msg_buff[3] <= alphanumeric_2[23:16];
                    msg_buff[4] <= alphanumeric_2[31:24];
                    msg_buff[5] <= 8'd0;
                  end
                  4'd3: begin
                    msg_buff[1] <= alphanumeric_3[7:0];
                    msg_buff[2] <= alphanumeric_3[15:8];
                    msg_buff[3] <= alphanumeric_3[23:16];
                    msg_buff[4] <= alphanumeric_3[31:24];
                    msg_buff[5] <= 8'd0;
                  end
                  4'd4: begin
                    msg_buff[1] <= alphanumeric_4[7:0];
                    msg_buff[2] <= alphanumeric_4[15:8];
                    msg_buff[3] <= alphanumeric_4[23:16];
                    msg_buff[4] <= alphanumeric_4[31:24];
                    msg_buff[5] <= 8'd0;
                  end
                  4'd5: begin
                    msg_buff[1] <= alphanumeric_5[7:0];
                    msg_buff[2] <= alphanumeric_5[15:8];
                    msg_buff[3] <= alphanumeric_5[23:16];
                    msg_buff[4] <= alphanumeric_5[31:24];
                    msg_buff[5] <= 8'd0;
                  end
                  4'd6: begin
                    msg_buff[1] <= alphanumeric_6[7:0];
                    msg_buff[2] <= alphanumeric_6[15:8];
                    msg_buff[3] <= alphanumeric_6[23:16];
                    msg_buff[4] <= alphanumeric_6[31:24];
                    msg_buff[5] <= 8'd0;
                  end
                  4'd7: begin
                    msg_buff[1] <= alphanumeric_7[7:0];
                    msg_buff[2] <= alphanumeric_7[15:8];
                    msg_buff[3] <= alphanumeric_7[23:16];
                    msg_buff[4] <= alphanumeric_7[31:24];
                    msg_buff[5] <= 8'd0;
                  end
                  4'd8: begin
                    msg_buff[1] <= alphanumeric_8[7:0];
                    msg_buff[2] <= alphanumeric_8[15:8];
                    msg_buff[3] <= alphanumeric_8[23:16];
                    msg_buff[4] <= alphanumeric_8[31:24];
                    msg_buff[5] <= 8'd0;
                  end
                  4'd9: begin
                    msg_buff[1] <= alphanumeric_9[7:0];
                    msg_buff[2] <= alphanumeric_9[15:8];
                    msg_buff[3] <= alphanumeric_9[23:16];
                    msg_buff[4] <= alphanumeric_9[31:24];
                    msg_buff[5] <= 8'd0;
                  end
                endcase
              else begin
                msg_buff[1] <= 8'd0;
                msg_buff[2] <= 8'd0;
                msg_buff[3] <= 8'd0;
                msg_buff[4] <= 8'd0;
                msg_buff[5] <= 8'd0;
              end
            end
            4'd3, 4'd2: begin
              msg_buff[1] <= 8'd0;
              msg_buff[2] <= 8'd0;
              msg_buff[3] <= 8'd0;
              msg_buff[4] <= 8'd0;
              msg_buff[5] <= 8'd0;
            end
            4'd1: begin
              msg_buff[0] <= 8'd0;
              msg_buff[1] <= 8'd0;
              msg_buff[2] <= 8'd0;
              msg_buff[3] <= 8'd0;
              msg_buff[4] <= 8'd0;
            end
            4'd0: begin
              msg_buff[1] <= 8'b0010_0000;
              msg_buff[2] <= 8'b0100_0011;
              msg_buff[3] <= 8'b1001_1000;
            end
          endcase
        end
        WHEEL_2, WHEEL_1, WHEEL_0, WEIGHT_2, WEIGHT_1, WEIGHT_0, HEIGHT_2, HEIGHT_1, HEIGHT_0: begin
          case(letter_num)
            4'd7, 4'd6, 4'd5: begin
              case(Digit[letter_num-4'd5])
                4'd0: begin
                  msg_buff[1] <= alphanumeric_0[7:0];
                  msg_buff[2] <= alphanumeric_0[15:8];
                  msg_buff[3] <= alphanumeric_0[23:16];
                  msg_buff[4] <= alphanumeric_0[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd1: begin
                  msg_buff[1] <= alphanumeric_1[7:0];
                  msg_buff[2] <= alphanumeric_1[15:8];
                  msg_buff[3] <= alphanumeric_1[23:16];
                  msg_buff[4] <= alphanumeric_1[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd2: begin
                  msg_buff[1] <= alphanumeric_2[7:0];
                  msg_buff[2] <= alphanumeric_2[15:8];
                  msg_buff[3] <= alphanumeric_2[23:16];
                  msg_buff[4] <= alphanumeric_2[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd3: begin
                  msg_buff[1] <= alphanumeric_3[7:0];
                  msg_buff[2] <= alphanumeric_3[15:8];
                  msg_buff[3] <= alphanumeric_3[23:16];
                  msg_buff[4] <= alphanumeric_3[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd4: begin
                  msg_buff[1] <= alphanumeric_4[7:0];
                  msg_buff[2] <= alphanumeric_4[15:8];
                  msg_buff[3] <= alphanumeric_4[23:16];
                  msg_buff[4] <= alphanumeric_4[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd5: begin
                  msg_buff[1] <= alphanumeric_5[7:0];
                  msg_buff[2] <= alphanumeric_5[15:8];
                  msg_buff[3] <= alphanumeric_5[23:16];
                  msg_buff[4] <= alphanumeric_5[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd6: begin
                  msg_buff[1] <= alphanumeric_6[7:0];
                  msg_buff[2] <= alphanumeric_6[15:8];
                  msg_buff[3] <= alphanumeric_6[23:16];
                  msg_buff[4] <= alphanumeric_6[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd7: begin
                  msg_buff[1] <= alphanumeric_7[7:0];
                  msg_buff[2] <= alphanumeric_7[15:8];
                  msg_buff[3] <= alphanumeric_7[23:16];
                  msg_buff[4] <= alphanumeric_7[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd8: begin
                  msg_buff[1] <= alphanumeric_8[7:0];
                  msg_buff[2] <= alphanumeric_8[15:8];
                  msg_buff[3] <= alphanumeric_8[23:16];
                  msg_buff[4] <= alphanumeric_8[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd9: begin
                  msg_buff[1] <= alphanumeric_9[7:0];
                  msg_buff[2] <= alphanumeric_9[15:8];
                  msg_buff[3] <= alphanumeric_9[23:16];
                  msg_buff[4] <= alphanumeric_9[31:24];
                  msg_buff[5] <= 8'd0;
                end
              endcase
            end
            4'd4, 4'd3, 4'd2: begin
              msg_buff[1] <= 8'd0;
              msg_buff[2] <= 8'd0;
              msg_buff[3] <= 8'd0;
              msg_buff[4] <= 8'd0;
              msg_buff[5] <= 8'd0;
            end
            4'd1: begin
              msg_buff[0] <= 8'd0;
              msg_buff[1] <= 8'd0;
              msg_buff[2] <= 8'd0;
              msg_buff[3] <= 8'd0;
              msg_buff[4] <= 8'd0;
            end
            4'd0: begin
              msg_buff[1] <= 8'b0010_0000;
              msg_buff[2] <= 8'b0100_0011;
              msg_buff[3] <= 8'b1001_1000;
            end
          endcase
        end
        AGE_1, AGE_0: begin
          case(letter_num)
            4'd7, 4'd6: begin
              case(Digit[letter_num-4'd6])
                4'd0: begin
                  msg_buff[1] <= alphanumeric_0[7:0];
                  msg_buff[2] <= alphanumeric_0[15:8];
                  msg_buff[3] <= alphanumeric_0[23:16];
                  msg_buff[4] <= alphanumeric_0[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd1: begin
                  msg_buff[1] <= alphanumeric_1[7:0];
                  msg_buff[2] <= alphanumeric_1[15:8];
                  msg_buff[3] <= alphanumeric_1[23:16];
                  msg_buff[4] <= alphanumeric_1[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd2: begin
                  msg_buff[1] <= alphanumeric_2[7:0];
                  msg_buff[2] <= alphanumeric_2[15:8];
                  msg_buff[3] <= alphanumeric_2[23:16];
                  msg_buff[4] <= alphanumeric_2[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd3: begin
                  msg_buff[1] <= alphanumeric_3[7:0];
                  msg_buff[2] <= alphanumeric_3[15:8];
                  msg_buff[3] <= alphanumeric_3[23:16];
                  msg_buff[4] <= alphanumeric_3[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd4: begin
                  msg_buff[1] <= alphanumeric_4[7:0];
                  msg_buff[2] <= alphanumeric_4[15:8];
                  msg_buff[3] <= alphanumeric_4[23:16];
                  msg_buff[4] <= alphanumeric_4[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd5: begin
                  msg_buff[1] <= alphanumeric_5[7:0];
                  msg_buff[2] <= alphanumeric_5[15:8];
                  msg_buff[3] <= alphanumeric_5[23:16];
                  msg_buff[4] <= alphanumeric_5[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd6: begin
                  msg_buff[1] <= alphanumeric_6[7:0];
                  msg_buff[2] <= alphanumeric_6[15:8];
                  msg_buff[3] <= alphanumeric_6[23:16];
                  msg_buff[4] <= alphanumeric_6[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd7: begin
                  msg_buff[1] <= alphanumeric_7[7:0];
                  msg_buff[2] <= alphanumeric_7[15:8];
                  msg_buff[3] <= alphanumeric_7[23:16];
                  msg_buff[4] <= alphanumeric_7[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd8: begin
                  msg_buff[1] <= alphanumeric_8[7:0];
                  msg_buff[2] <= alphanumeric_8[15:8];
                  msg_buff[3] <= alphanumeric_8[23:16];
                  msg_buff[4] <= alphanumeric_8[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd9: begin
                  msg_buff[1] <= alphanumeric_9[7:0];
                  msg_buff[2] <= alphanumeric_9[15:8];
                  msg_buff[3] <= alphanumeric_9[23:16];
                  msg_buff[4] <= alphanumeric_9[31:24];
                  msg_buff[5] <= 8'd0;
                end
              endcase
            end
            4'd5, 4'd4, 4'd3, 4'd2: begin
              msg_buff[1] <= 8'd0;
              msg_buff[2] <= 8'd0;
              msg_buff[3] <= 8'd0;
              msg_buff[4] <= 8'd0;
              msg_buff[5] <= 8'd0;
            end
            4'd1: begin
              msg_buff[0] <= 8'd0;
              msg_buff[1] <= 8'd0;
              msg_buff[2] <= 8'd0;
              msg_buff[3] <= 8'd0;
              msg_buff[4] <= 8'd0;
            end
            4'd0: begin
              msg_buff[1] <= 8'b0010_0000;
              msg_buff[2] <= 8'b0100_0011;
              msg_buff[3] <= 8'b1001_1000;
            end
          endcase
        end
        GENDER: begin
          case(letter_num)
            4'd7: begin
              case(Digit[0])
                4'd0: begin
                  msg_buff[1] <= alphanumeric_M[7:0];
                  msg_buff[2] <= alphanumeric_M[15:8];
                  msg_buff[3] <= alphanumeric_M[23:16];
                  msg_buff[4] <= alphanumeric_M[31:24];
                  msg_buff[5] <= 8'd0;
                end
                4'd1: begin
                  msg_buff[1] <= alphanumeric_F[7:0];
                  msg_buff[2] <= alphanumeric_F[15:8];
                  msg_buff[3] <= alphanumeric_F[23:16];
                  msg_buff[4] <= alphanumeric_F[31:24];
                  msg_buff[5] <= 8'd0;
                end
              endcase
            end
            4'd6, 4'd5, 4'd4, 4'd3, 4'd2: begin
              msg_buff[1] <= 8'd0;
              msg_buff[2] <= 8'd0;
              msg_buff[3] <= 8'd0;
              msg_buff[4] <= 8'd0;
              msg_buff[5] <= 8'd0;
            end
            4'd1: begin
              msg_buff[0] <= 8'd0;
              msg_buff[1] <= 8'd0;
              msg_buff[2] <= 8'd0;
              msg_buff[3] <= 8'd0;
              msg_buff[4] <= 8'd0;
            end
            4'd0: begin
              msg_buff[1] <= 8'b0010_0000;
              msg_buff[2] <= 8'b0100_0011;
              msg_buff[3] <= 8'b1001_1000;
            end
          endcase
        end
      endcase
    end
    default: begin
      msg_buff[0] <= msg_buff[0];
      msg_buff[1] <= msg_buff[1];
      msg_buff[2] <= msg_buff[2];
      msg_buff[3] <= msg_buff[3];
      msg_buff[4] <= msg_buff[4];
      msg_buff[5] <= msg_buff[5];
      msg_buff[6] <= msg_buff[6];
      msg_buff[7] <= msg_buff[7];
    end
  endcase
end

// Message length buffer
always_ff @ (posedge Clock or negedge nReset)
if(!nReset)
  msg_len <= 4'd0;
else
  case(lcd_state)
    LCD_RESET: begin
      // None
    end
    LCD_SETUP: begin
      if(lcd_state_prev == LCD_RESET)
        msg_len <= 4'd8;
      else
        msg_len <= msg_len;
    end
    LCD_IDLE: begin
      // None
    end
    LCD_DRAW_METRIC_TITLE: begin
      case(letter_num)
        4'd8: begin
          msg_len <= msg_len;
        end
        4'd7, 4'd6, 4'd5, 4'd4, 4'd3, 4'd2: begin
          msg_len <= 4'd6;
        end
        4'd1: begin
          msg_len <= 4'd5;
        end
        4'd0: begin
          msg_len <= 4'd4;
        end
      endcase
    end
    LCD_DRAW_METRIC_VALUE: begin
      case(letter_num)
        4'd8: begin
          msg_len <= msg_len;
        end
        4'd7, 4'd6, 4'd5, 4'd4, 4'd3, 4'd2: begin
          msg_len <= 4'd6;
        end
        4'd1: begin
          msg_len <= 4'd5;
        end
        4'd0: begin
          msg_len <= 4'd4;
        end
      endcase
    end
    default: begin
    end
  endcase

// Current message buffer
always_ff @ (posedge Clock or negedge nReset)
if(!nReset)
  curr_msg <= 4'd0;
else
  case(lcd_state)
    LCD_RESET: begin
      // None
    end
    LCD_SETUP: begin
      if(lcd_state_prev == LCD_RESET)
        curr_msg <= 4'd8;
      else
        if((curr_msg == 4'b1)&(byte_counter == 3'b0)) begin
          if(lcd_setup_wait == 10'd0)
            curr_msg <= 4'd0;
          else
            curr_msg <= 4'd1;
        end
        else
          if (byte_counter == 3'd0)
            curr_msg <= curr_msg - 4'd1;
          else
            curr_msg <= curr_msg;
    end
    LCD_IDLE: begin
      // None
    end
    LCD_DRAW_METRIC_TITLE: begin
      case(letter_num)
        4'd8, 4'd7, 4'd6, 4'd5, 4'd4, 4'd3, 4'd2, 4'd1: begin
          if((curr_msg == 4'd1) & (byte_counter == 3'd0))
            curr_msg <= 4'd5;
          else
            if (byte_counter == 3'd0)
              curr_msg <= curr_msg - 4'd1;
            else
              curr_msg <= curr_msg;
        end
        4'd0: begin
          if(lcd_state_prev == LCD_IDLE)
            curr_msg <= 4'd3;
          else
            curr_msg <= 4'd0;
        end
      endcase
    end
    LCD_DRAW_METRIC_VALUE: begin
      case(letter_num)
        4'd8, 4'd7, 4'd6, 4'd5, 4'd4, 4'd3, 4'd2, 4'd1: begin
          if((curr_msg == 4'd1) & (byte_counter == 3'd0))
            curr_msg <= 4'd5;
          else
            if (byte_counter == 3'd0)
              curr_msg <= curr_msg - 4'd1;
            else
              curr_msg <= curr_msg;
        end
        4'd0: begin
          if(lcd_state_prev == LCD_IDLE)
            curr_msg <= 4'd3;
          else
            curr_msg <= 4'd0;
        end
      endcase
    end
    default: begin
    end
  endcase

// Byte counter
always_ff @ (posedge Clock or negedge nReset)
if(!nReset)
  byte_counter <= 3'd7;
else
  if(byte_counter == 3'd0)
    byte_counter <= 3'd7;
  else
    if(serial_clk_on & !(curr_msg == 0))
      byte_counter <= byte_counter - 3'd1;
    else
      byte_counter <= byte_counter;

// Number of letters
always_ff @ (posedge Clock or negedge nReset)
if(!nReset)
  letter_num <= 4'd0;
else
  case(lcd_state)
    LCD_RESET: begin
      // None
    end
    LCD_SETUP: begin
      // None
    end
    LCD_IDLE: begin
      // None
    end
    LCD_DRAW_METRIC_TITLE: begin
      if((letter_num == 4'd0) & (lcd_state_prev == LCD_IDLE))
        letter_num <= 4'd8;
      else
        if((letter_num == 4'd1) & (curr_msg == 4'b1) & (byte_counter == 3'd1))
          letter_num <= 4'd0;
        else
          if((curr_msg == 4'b1) & (byte_counter == 3'd1))
            letter_num <= letter_num - 4'd1;
          else
            letter_num <= letter_num;
    end
    LCD_DRAW_METRIC_VALUE: begin
      if((letter_num == 4'd0) & (lcd_state_prev == LCD_IDLE))
        letter_num <= 4'd8;
      else
        if((letter_num == 4'd1) & (curr_msg == 4'b1) & (byte_counter == 3'd1))
          letter_num <= 4'd0;
        else
          if((curr_msg == 4'b1) & (byte_counter == 3'd1))
            letter_num <= letter_num - 4'd1;
          else
            letter_num <= letter_num;
    end
    default: begin
    end
  endcase

reg sclk_state;
wire sclk_setup = !(lcd_setup_wait == 10'd0) & (lcd_state == LCD_SETUP);
wire sclk_draw = !((curr_msg == 1)&(letter_num == 4'd0)&(byte_counter == 3'd0))
                 & (  (lcd_state == LCD_DRAW_METRIC_VALUE)
                    | (lcd_state == LCD_DRAW_METRIC_TITLE));

always_ff @ (posedge Clock or negedge nReset)
if(!nReset)
  sclk_state <= 1'b0;
else
  if(spi_state == SPI_TRANSMIT)
    if(sclk_setup)
      sclk_state <= 1'b1;
    else
      if(sclk_draw)
        sclk_state <= 1'b1;
      else
        sclk_state <= 1'b0;
  else
    sclk_state <= 1'b0;

reg sclk_disabler;
wire sclk_disabler_setup = (lcd_setup_wait == 10'd0) & (lcd_state == LCD_SETUP);
wire sclk_disabler_draw = ((curr_msg == 1)&(letter_num == 4'd0)&(byte_counter == 3'd0))
                          & (  (lcd_state == LCD_DRAW_METRIC_VALUE)
                             | (lcd_state == LCD_DRAW_METRIC_TITLE));

always_ff @ (negedge Clock or negedge nReset)
if(!nReset)
  sclk_disabler <= 1'b1;
else
  if(spi_state == SPI_TRANSMIT)
    if(sclk_disabler_setup)
      sclk_disabler <= 1'b0;
    else
      if(sclk_disabler_draw)
        sclk_disabler <= 1'b0;
      else
        sclk_disabler <= 1'b1;
  else
    sclk_disabler <= 1'b1;

///---------------------------------------------------------------------
//  Wire signal assigns goes here.
///---------------------------------------------------------------------

assign MEMRefreshTrig = (MemData != MemInput) ? 1'b1 : 1'b0;
assign DISPRefreshTrig = (DisplayPrev != Display) ? 1'b1 : 1'b0;

assign serial_data_on = (spi_state == SPI_TRANSMIT) & !(curr_msg == 0);
assign serial_clk_on = (spi_state_prev == SPI_TRANSMIT);

assign SDIN = msg_buff[msg_len-curr_msg][byte_counter] & serial_data_on;
assign SCLK = !(Clock & sclk_state & sclk_disabler);
assign DnC  = (((lcd_state_prev == LCD_SETUP) & (lcd_setup_wait < 13'd4031)) |
               (((lcd_state_prev == LCD_DRAW_METRIC_TITLE) | (lcd_state_prev == LCD_DRAW_METRIC_VALUE))& !(letter_num == 4'd8))) & (byte_counter == 3'd0) & !(msg_len == 4'd4);
assign nRES = !((lcd_state == LCD_RESET) & (lcd_reset_wait == 1'b1));
assign nSCE = !sclk_state;
assign Display = display_t'(display);

endmodule
