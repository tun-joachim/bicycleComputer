///////////////////////////////////////////////////////////////////////
//
// LED display module
//
// The arrangement of the digits and segments of the L.E.D. display is
// shown below. Each digit has seven segments marked A-G and a decimal point
// to the right marked DP. The most significant digit is Digit 3.
//
//        Digit 3         Digit 2         Digit 1         Digit 0
//
//         --A--           --A--           --A--           --A--
//        |     |         |     |         |     |         |     |
//        F     B         F     B         F     B         F     B
//        |     |         |     |         |     |         |     |
//         --G--           --G--           --G--           --G--
//        |     |         |     |         |     |         |     |
//        E     C         E     C         E     C         E     C
//        |     |         |     |         |     |         |     |
//         --D--   *DP     --D--   *DP     --D--   *DP     --D--   *DP
//
// The display is a common cathode multiplexed display. Thus a segment is
// lit if and only if the relevant "SegX" line is taken high and the
// relevant "nDigit" line is taken low.
//
///////////////////////////////////////////////////////////////////////

`ifndef LED_NUM_DIGITS
  `define LED_NUM_DIGITS 4
`endif

`ifndef MEM_REFRESH
  `define MEM_REFRESH 1280
`endif

`ifndef LED_REFRESH
  `define LED_REFRESH 50
`endif

module led_displays (
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

  //Input
  MemInput,
  display,
  Clock,
  nReset
);

timeunit 1ns;
timeprecision 100ps;

typedef enum logic [4:0] {
  ODOMETER, TRIP_TIMER, SPEEDOMETER, CADENCE, CALORIES, AVE_SPEED, WHEEL_2, WHEEL_1, WHEEL_0, WEIGHT_2, WEIGHT_1, WEIGHT_0, HEIGHT_2, HEIGHT_1, HEIGHT_0, AGE_1, AGE_0, GENDER
} display_t;

output [`LED_NUM_DIGITS-1:0] nDigit;
output SegA, SegB, SegC, SegD, SegE, SegF, SegG, DP;
input [15:0] MemInput;
input [4:0] display;
display_t Display;
input Clock, nReset;

wire MEMRefreshTrig;
wire LEDRefreshTrig;

reg [15:0] MemData, TruncData;
reg [7:0] LEDRefreshCounter, SegmentReg; // SegmentReg = {SegA,SegB,SegC,SegD,SegE,SegF,SegG,DP}
reg [4:0] Count;
reg [3:0] Digit [6:0]; // Digit = {Digit0,Digit1,Digit2,RadixPoint,Ones,Tens,Hundreds}
display_t DisplayPrev;
reg [`LED_NUM_DIGITS-1:0] DisplayDigit;
reg [`LED_NUM_DIGITS-1:0] nDigitReg;

// Update Display Logic
always_ff @ (posedge Clock or negedge nReset)
if (!nReset) begin
  Digit[0] <= 4'd0;
  Digit[1] <= 4'd0;
  Digit[2] <= 4'd0;
  Digit[3] <= 4'd0;
end else begin
  if (Count == 4'd0) case(Display)
    ODOMETER: begin
      if (MemData[15:4] < 12'd100) begin
        Digit[0] <= MemData[3:0];
        Digit[1] <= Digit[4];
        Digit[2] <= Digit[5];
        Digit[3] <= {Digit[3][3],3'b010};
      end
      else begin  // >100km
        Digit[0] <= Digit[4];
        Digit[1] <= Digit[5];
        Digit[2] <= Digit[6];
        Digit[3] <= {Digit[3][3],3'b001};
      end
    end
    TRIP_TIMER: begin
      Digit[0] <= Digit[4]; // ones_minute
      Digit[1] <= Digit[5]; // tens_minute
      Digit[2] <= Digit[6]; // hours
      Digit[3] <= {Digit[3][3],3'b100};
    end
    SPEEDOMETER: begin
      Digit[0] <= Digit[4];
      Digit[1] <= Digit[5];
      Digit[2] <= Digit[6];
      if (MemData < 16'd1_000)
        Digit[3] <= {Digit[3][3],3'b100};
      else
        Digit[3] <= {Digit[3][3],3'b010};
    end
    CADENCE: begin
      Digit[0] <= Digit[4];
      Digit[1] <= Digit[5];
      Digit[2] <= Digit[6];
      if (MemData < 16'd10_000)
        Digit[3] <= {Digit[3][3],3'b010};
      else
        Digit[3] <= {Digit[3][3],3'b001};
    end
    CALORIES: begin
      Digit[0] <= Digit[4];
      Digit[1] <= Digit[5];
      Digit[2] <= Digit[6];
      if (MemData < 16'd10_000)
        Digit[3] <= {Digit[3][3],3'b010};
      else
        Digit[3] <= {Digit[3][3],3'b001};
    end
    AVE_SPEED: begin
      Digit[0] <= Digit[4];
      Digit[1] <= Digit[5];
      Digit[2] <= Digit[6];
      if (MemData < 16'd1_000)
        Digit[3] <= {Digit[3][3],3'b100};
      else
        Digit[3] <= {Digit[3][3],3'b010};
    end
    WHEEL_2, WHEEL_1, WHEEL_0: begin
      Digit[0] <= Digit[4];
      Digit[1] <= Digit[5];
      Digit[2] <= Digit[6];
      
      if(Display == WHEEL_2)
        Digit[3] <= {Digit[3][3],3'b100};
      else
        if(Display == WHEEL_1)
          Digit[3] <= {Digit[3][3],3'b010};
        else
          Digit[3] <= {Digit[3][3],3'b001};
    end
    WEIGHT_2, WEIGHT_1, WEIGHT_0: begin
      Digit[0] <= Digit[4];
      Digit[1] <= Digit[5];
      Digit[2] <= Digit[6];
      
      if(Display == WEIGHT_2)
        Digit[3] <= {Digit[3][3],3'b100};
      else
        if(Display == WEIGHT_1)
          Digit[3] <= {Digit[3][3],3'b010};
        else
          Digit[3] <= {Digit[3][3],3'b001};
    end
    HEIGHT_2, HEIGHT_1, HEIGHT_0: begin
      Digit[0] <= Digit[4];
      Digit[1] <= Digit[5];
      Digit[2] <= Digit[6];
      
      if(Display == HEIGHT_2)
        Digit[3] <= {Digit[3][3],3'b100};
      else
        if(Display == HEIGHT_1)
          Digit[3] <= {Digit[3][3],3'b010};
        else
          Digit[3] <= {Digit[3][3],3'b001};  
    end 
    AGE_1, AGE_0: begin
      Digit[0] <= Digit[4];
      Digit[1] <= Digit[5];
      Digit[2] <= Digit[6];
      
      if(Display == AGE_1)
        Digit[3] <= {Digit[3][3],3'b010};
      else
        Digit[3] <= {Digit[3][3],3'b001};
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
      Digit[3] <= Digit[3];
    end
  endcase
  else begin
    Digit[0] <= Digit[0];
    Digit[1] <= Digit[1];
    Digit[2] <= Digit[2];
    Digit[3] <= Digit[3];
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
      Digit[6] <= TruncData[11:8];
      Count <= Count - 5'd1;
    end
    GENDER: begin
      Digit[4] <= TruncData[3:0];
      Digit[5] <= TruncData[3:0];
      Digit[6] <= TruncData[11:8];
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

// LEDRefreshCounter
always_ff @ (posedge Clock or negedge nReset)
if (!nReset)
  LEDRefreshCounter <= 8'd0;
else if (LEDRefreshCounter == `LED_REFRESH)
  LEDRefreshCounter <= 8'd0;
else
  LEDRefreshCounter <= LEDRefreshCounter + 8'd1;

// Handles the DisplayDigit
always_ff @ (posedge Clock or negedge nReset)
if (!nReset) DisplayDigit <= 4'd8;
else if (LEDRefreshTrig)
  case (DisplayDigit)
    4'd1   : DisplayDigit <= 4'd8;
    4'd2   : DisplayDigit <= 4'd1;
    4'd4   : DisplayDigit <= 4'd2;
    4'd8   : DisplayDigit <= 4'd4;
    default: DisplayDigit <= 4'd8;
  endcase
else DisplayDigit <= DisplayDigit;


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
      TruncData <= {15'd0,MemInput[10]};
  endcase
end
else begin
  MemData <= MemData;
  TruncData <= TruncData;
end

// LED Display
always_ff @ (posedge Clock or negedge nReset)
if (!nReset) begin
  SegmentReg <= 8'd0;
  nDigitReg  <= 4'd7;
end 
else begin
  case (DisplayDigit)
    4'd1, 4'd2, 4'd4: begin // nDigit_0
      if(Display == GENDER)
        if(DisplayDigit == 4'd4)
          SegmentReg <= {7'b000_0000,SegmentReg[0]};
        else
          case((DisplayDigit == 4'd1) ? Digit[0] : Digit[1])
            4'd0   : if(DisplayDigit == 4'd1)
                       SegmentReg <= {7'b110_0110,SegmentReg[0]};
                     else
                       if(DisplayDigit == 4'd2)
                         SegmentReg <= {7'b111_0010,SegmentReg[0]};
                       else
                         SegmentReg <= {7'b000_0000,SegmentReg[0]};
            4'd1   : if(DisplayDigit == 4'd1)
                       SegmentReg <= {7'b100_0111,SegmentReg[0]};
                     else
                       SegmentReg <= {7'b000_0000,SegmentReg[0]};
            default: SegmentReg <= {7'b000_0000,SegmentReg[0]};
          endcase
      else
        if((Display == GENDER)&(DisplayDigit == 4'd4))
          SegmentReg <= {7'b000_0000,SegmentReg[0]};
        else
          case((DisplayDigit == 4'd1) ? Digit[0] : ( (DisplayDigit == 4'd2) ? Digit[1] : Digit [2] ))
            4'd0   : SegmentReg <= {7'b111_1110,SegmentReg[0]}; 
            4'd1   : SegmentReg <= {7'b011_0000,SegmentReg[0]};
            4'd2   : SegmentReg <= {7'b110_1101,SegmentReg[0]};
            4'd3   : SegmentReg <= {7'b111_1001,SegmentReg[0]};
            4'd4   : SegmentReg <= {7'b011_0011,SegmentReg[0]};
            4'd5   : SegmentReg <= {7'b101_1011,SegmentReg[0]};
            4'd6   : SegmentReg <= {7'b101_1111,SegmentReg[0]};
            4'd7   : SegmentReg <= {7'b111_0000,SegmentReg[0]};
            4'd8   : SegmentReg <= {7'b111_1111,SegmentReg[0]};
            4'd9   : SegmentReg <= {7'b111_1011,SegmentReg[0]};
            default: SegmentReg <= {7'b000_0001,SegmentReg[0]};
          endcase
          if(DisplayDigit == 4'd1)
            SegmentReg[0] <= Digit[3][0];
          else
            if(DisplayDigit == 4'd2)
              SegmentReg[0] <= Digit[3][1];
            else
              SegmentReg[0] <= Digit[3][2];
    end
    4'd8: begin
      case(Display)
        ODOMETER    : SegmentReg <= {7'b011_1101,1'b0};
        TRIP_TIMER  : SegmentReg <= {7'b000_1111,1'b0};
        SPEEDOMETER : SegmentReg <= {7'b001_1000,1'b0};
        CADENCE     : SegmentReg <= {7'b000_1101,1'b0};
        AVE_SPEED   : SegmentReg <= {7'b101_1011,1'b0};
        CALORIES    : SegmentReg <= {7'b100_1110,1'b0};
        WHEEL_2, WHEEL_1 ,WHEEL_0: 
          SegmentReg <= {7'b001_1101,1'b1};
        WEIGHT_2, WEIGHT_1, WEIGHT_0:
          SegmentReg <= {7'b001_1100,1'b1};
        HEIGHT_2, HEIGHT_1, HEIGHT_0:
          SegmentReg <= {7'b011_0111,1'b1};
        AGE_1, AGE_0:
          SegmentReg <= {7'b111_0111,1'b1};
        GENDER:
          SegmentReg <= {7'b101_1110,1'b1};
        default: SegmentReg <= {7'b000_0001,SegmentReg[0]};
      endcase
      //SegmentReg[0] <= Digit[3][3];
    end
    default: SegmentReg <= {7'b000_0001,SegmentReg[0]};
  endcase
  nDigitReg <= ~DisplayDigit;
end

assign MEMRefreshTrig = ((DisplayPrev != Display) ||
                         (MemData != MemInput)) ? 1'b1 : 1'b0;
assign LEDRefreshTrig = (LEDRefreshCounter == `LED_REFRESH) ? 1'b1 : 1'b0;
assign SegA = SegmentReg[7];
assign SegB = SegmentReg[6];
assign SegC = SegmentReg[5];
assign SegD = SegmentReg[4];
assign SegE = SegmentReg[3];
assign SegF = SegmentReg[2];
assign SegG = SegmentReg[1];
assign DP   = SegmentReg[0];
assign nDigit = nDigitReg;
assign Display = display_t'(display);

endmodule
