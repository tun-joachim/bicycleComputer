module modeCal (
    input Clock, nReset,
    input [15:0] fork_time, crank_time,
    input [15:0] mem_read,
    input clear, update,
    input [2:0] incr,
    input [4:0] displayMode,
    input wheelrev_trigger, second_trigger, wheelmenu_trigger, //userProf_trigger,
    output reg [15:0] mem_write,
    output reg [3:0] addr,
    output logic write_enable
);


enum logic [5:0] {WAIT, WHEEL_WR_2, WHEEL_WR_1, WHEEL_WR_0, WHEEL_CLR, WHEEL_END,
				  ODO_WR_L, ODO_WR_H, ODO_CLR_L, ODO_CLR_H, ODO_END,
				  TRIP_WR, TRIP_CLR, TRIP_END,
				  SPEED_WR, SPEED_END,
				  CAD_WR, CAD_END,
				  USR_W2, USR_W1, USR_W0, USR_H2, USR_H1, USR_H0, 
				  USR_AGE1, USR_AGE0, USR_GENDER, USR_END,
				  WEIGHT_SET, HEIGHT_SET, AGE_GENDER_SET,
				  WEIGHT_READ, HEIGHT_READ, AGE_READ,
				  CAL_WR, CAL_CLR, CAL_END,
				  AVG_R_T, AVG_R_DH, AVG_R_DL, AVG_WR, AVG_END} state, state_prev;

timeunit 1ns;
timeprecision 100ps;

reg [15:0] wheel_config;
reg [8:0] modeUpdate;
reg [15:0] totalTime;
reg [31:0] totalDist;
reg [15:0] BMR;
reg [15:0] avgSpd;
reg [7:0] weight, height, age;
wire odo_complete, trip_complete, speed_complete, speed_update, cad_complete;
wire wheelmenu_complete; //, userProf_complete;
wire avg_complete;
wire cal_complete;
wire incr2, incr1, incr0;

reg  wheelrev_sync;
reg  wheelrev_sync_old;
wire wheelrev_complete;

always_ff @ (posedge Clock or negedge nReset)
if (!nReset) wheelrev_sync <= 1'b0;
else         wheelrev_sync <= wheelrev_trigger;

always_ff @ (posedge Clock or negedge nReset)
if (!nReset) wheelrev_sync_old <= 1'b0;
else         wheelrev_sync_old <= wheelrev_sync;

assign wheelrev_complete = (wheelrev_sync) & (!wheelrev_sync_old);

// reg [3:0] modeUpdate = {ODO_UPDATE, TIMER_UPDATE, SPEEDOMETER_UPDATE, CADENCE_UPDATE} 
//always_ff @ (posedge Clock or negedge nReset)
//if
//else begin
// if (odo_reset) reg[0]<= 0;
// else if (wheelrev_complete) reg[0] <= 1;
// else reg[0] <= reg[0];
//
// if (timer_reset) reg[1] <=0;
// else if (timer_sec) reg[1] <=1;
// else reg[1] <= reg[1];
// 
//end

// modeUpdate reg
//
// 0: Odometer
// 1: Trip timer
// 2: Speed
// 3: Cadence
// 4: Calorie
// 5: Average speed
// 6: Wheelsize menu
// 7: User profile menu

always_ff @ (posedge Clock or negedge nReset)
if (!nReset)	modeUpdate <= 8'b0;
else begin
	if (odo_complete) modeUpdate[0] <= 0;
	else if (wheelrev_complete) modeUpdate[0] <= 1;
	else modeUpdate[0] <= modeUpdate[0];
	
	if (trip_complete) modeUpdate[1] <=0;
	else if (second_trigger) modeUpdate[1] <= 1;
	else modeUpdate[1] <= modeUpdate[1];
	
	if (speed_complete) modeUpdate[2] <=0;
	else if (speed_update) modeUpdate[2] <= 1;
	else modeUpdate[2] <= modeUpdate[2];
	
	if (cad_complete) modeUpdate[3] <=0;
	else if (speed_complete) modeUpdate[3] <= 1;
	else modeUpdate[3] <= modeUpdate[3];
	
	if (cal_complete) modeUpdate[4] <= 0;
	else if (avg_complete) modeUpdate[4] <= 1;
	else modeUpdate[4] <= modeUpdate[4];
	
	if (avg_complete) modeUpdate[5] <= 0;
	else if (cad_complete) modeUpdate[5] <= 1;
	else modeUpdate[5] <= modeUpdate[5];
		
	if (wheelmenu_complete) modeUpdate[6] <= 0;
	else if (wheelmenu_trigger) modeUpdate[6] <= 1;
	else modeUpdate[6] <= modeUpdate [6];
	/*
	if (userProf_complete) modeUpdate[7] <= 0;
	else if (userProf_trigger) begin
	  modeUpdate[7] <= 1;
	  modeUpdate[6] <= 0;
	end else modeUpdate[7] <= modeUpdate[7];
	*/
end

reg [7:0] updateSpeed;

always_ff @ (posedge Clock or negedge nReset)
if (!nReset) updateSpeed <= 8'd0;
else if (speed_update) updateSpeed <= 8'd0;
else updateSpeed <= updateSpeed + 8'd1;

assign odo_complete   = (state == ODO_END);
assign trip_complete  = (state == TRIP_END);
assign speed_complete = (state == SPEED_END);
assign speed_update   = updateSpeed == 8'd150;
assign cad_complete   = (state == CAD_END);
assign cal_complete = (state == CAL_END);
assign avg_complete = (state == AVG_END);
assign wheelmenu_complete = (state == USR_END);
//assign wheelmenu_complete = (state == WHEEL_END);
//assign userProf_complete = (state == USR_END);
// assign wheel_config = 16'd214;
//assign BMR = 16'd1698;
assign incr2 = incr[2];
assign incr1 = incr[1];
assign incr0 = incr[0];
//assign weight = 8'd70;
//assign height = 8'd175;
//assign age = 8'd23;

// Memory Address
//
// 0: Odometer_H
// 1: Trip timer
// 2: Speed
// 3: Cadence
// 4: Calorie
// 5: Average speed
// 6: Odometer_L
// 7: Wheel config
// 8: User weight {2'b0, 2'bStatus, 4'bDigit2, 4'bDigit1, 4'bDigit0}
// 9: User height {2'b0, 2'bStatus, 4'bDigit2, 4'bDigit1, 4'bDigit0}
//10: User Age & Gender {6'b0, 1'bGender, 1'bStatus, 4'dDigit1, 4'dDigit0}

always_ff @ (posedge Clock or negedge nReset)
if (!nReset) begin
  // mem_write <= 16'd0;
  mem_write <= {2'b00, 2'b10, 4'd2, 4'd1, 4'd4};//----- DEFAULT WHEEL: 214cm
  addr <= 4'd7;					//----- WHEEL CONFIG
  // addr <= 4'd6;				//----- ODO
  // addr <= 4'd1;				//----- TRIP
  // addr <= 4'd2;				//----- SPEED
  // addr <= 4'd3;				//----- CADENCE
  write_enable <= 1'b1;
  state <= WHEEL_CLR;
  state_prev <= WHEEL_CLR;
  // state <= ODO_CLR_L;		//----- ODO Test
  // state_prev <= ODO_CLR_L;
  // state <= TRIP_CLR;			//----- TRIP Test
  // state_prev <= TRIP_CLR;
  // state <= SPEED_WAIT;		//----- SPEED Test
  // state_prev <= SPEED_WAIT;
  // state <= CAD_WAIT;			//----- CADENCE Test
  // state_prev <= CAD_WAIT;
end else begin
  if (clear) begin
    mem_write <= 16'd0;
    addr <= 4'd6;
    write_enable <= 1;
    state <= ODO_CLR_L;
  end else case (state)
  WAIT: begin
    mem_write <= 16'd0;
    // addr <= 4'd6;
    write_enable <= 0;
    if (modeUpdate[0]) begin
      addr <= 4'd6;
      state <= ODO_WR_L;
    end else if (modeUpdate[1]) begin
      addr <= 4'd1;
      state <= TRIP_WR;
    end	else if (modeUpdate[2]) begin
      addr <= 4'd2;
      state <= SPEED_WR;
    end	else if (modeUpdate[3]) begin
      addr <= 4'd3;
      state <= CAD_WR;
    end else if (modeUpdate[4]) begin
      addr <= 4'd4;
      state <= CAL_WR;
    end else if (modeUpdate[5]) begin
      addr <= 4'd1;
      state <= AVG_R_T;
    end else if (modeUpdate[6]) begin
      addr <= 4'd7;
      state <= WHEEL_WR_2;
    /*
    end else if (modeUpdate[7]) begin
      addr <= 4'd8;
      state <= USR_W2;
    */
    end else begin
      state <= WAIT;
    end
  end
  WHEEL_WR_2: begin
    addr <= 4'd7;  
    if (incr2) begin
      write_enable <= 1;
      if (mem_read[11:8]<9)
        mem_write <= {2'b0, mem_read[13:12], mem_read[11:8]+4'd1, mem_read[7:0]};
      else
        mem_write <= {2'b0, mem_read[13:12], 4'd0, mem_read[7:0]};
      state <= WHEEL_WR_2;
    end else if (update) begin
      write_enable <= 1;
      mem_write <= {mem_read[15:14], 2'b01, mem_read[11:0]};
      state <= WHEEL_WR_1;
    end else begin
      write_enable <= 0;
      state <= WHEEL_WR_2;
    end
  /*
    if (userProf_trigger) begin
      addr <= 4'd8;
      write_enable <= 0;
      mem_write <= 16'd0;
      state <= USR_W2;
    end else begin
      addr <= 4'd7;  
      if (incr2) begin
        write_enable <= 1;
        if (mem_read[11:8]<9)
          mem_write <= {2'b0, mem_read[13:12], mem_read[11:8]+4'd1, mem_read[7:0]};
        else
          mem_write <= {2'b0, mem_read[13:12], 4'd0, mem_read[7:0]};
        state <= WHEEL_WR_2;
      end else if (update) begin
        write_enable <= 1;
        mem_write <= {mem_read[15:14], 2'b01, mem_read[11:0]};
        state <= WHEEL_WR_1;
      end else begin
        write_enable <= 0;
        state <= WHEEL_WR_2;
      end
    end
    */
  end
  WHEEL_WR_1: begin
    addr <= 4'd7;  
    if (incr1) begin
      write_enable <= 1;
      if (mem_read[7:4]<9)
        mem_write <= {2'b0, mem_read[13:12], mem_read[11:8], mem_read[7:4]+4'd1, mem_read[3:0]};
      else
        mem_write <= {2'b0, mem_read[13:12], mem_read[11:8], 4'd0, mem_read[3:0]};
      state <= WHEEL_WR_1;
    end else if (update) begin
      write_enable <= 1;
      mem_write <= {mem_read[15:14], 2'b00, mem_read[11:0]};
      state <= WHEEL_WR_0;
    end else begin
      write_enable <= 0;
      state <= WHEEL_WR_1;
    end
  end
  WHEEL_WR_0: begin
    addr <= 4'd7;  
    if (incr0) begin
      write_enable <= 1;
      if (mem_read[3:0]<9)
        mem_write <= {2'b0, mem_read[13:4], mem_read[3:0]+4'd1};
      else
        mem_write <= {2'b0, mem_read[13:4], 4'd0};
      state <= WHEEL_WR_0;
    end else if (update) begin
      write_enable <= 1;
      mem_write <= {mem_read[15:14], 2'b10, mem_read[11:0]};
      state <= WHEEL_END;
    end else begin
      write_enable <= 0;
      state <= WHEEL_WR_0;
    end
  end
  WHEEL_CLR: begin
    mem_write <= 16'd0;
    addr <= 4'd7;
    write_enable <= 0;
    state <= WHEEL_END;
  end
  WHEEL_END: begin
    if(state_prev == WHEEL_WR_0) begin
      mem_write <= 16'd0;
      addr <= 4'd8;
      write_enable <= 0;
      //wheel_config <= mem_read[11:8]*100 + mem_read[7:4]*10 + mem_read[3:0];     // BCD2BIN
      state <= USR_W2;
    end else begin
      mem_write <= 16'd0;
      addr <= 4'd6;
      write_enable <= 1;
      state <= ODO_CLR_L;
      //wheel_config <= mem_read[11:8]*100 + mem_read[7:4]*10 + mem_read[3:0];     // BCD2BIN
    end
    wheel_config <= mem_read[11:8]*100 + mem_read[7:4]*10 + mem_read[3:0];
    /*
    mem_write <= 16'd0;
    //addr <= 4'd6;
    addr <= 4'd8;
    write_enable <= 0;
    //write_enable <= 1;
    wheel_config <= mem_read[11:8]*100 + mem_read[7:4]*10 + mem_read[3:0];
    //state <= ODO_CLR_L;
    state <= USR_W2;
    */
  end
  ODO_WR_L: begin
    write_enable <= 1;
    addr <= 4'd6;
    if (mem_read >= 10_000) begin
      mem_write <= mem_read - 16'd10_000 + wheel_config;
      state <= ODO_WR_H;
    end else begin
      mem_write <= mem_read + wheel_config;
      state <= ODO_END;
    end
  end
  ODO_WR_H: begin
    mem_write <= 16'd0;
    addr <= 4'd0;
    write_enable <= 1;
    state <= ODO_END;
  end
  ODO_CLR_L: begin
    if (state_prev==WHEEL_END) begin
      mem_write <= 16'd0;
      addr <= 4'd0;
      write_enable <= 1;
      state <= ODO_CLR_H;
    end else begin
      mem_write <= 16'd0;
      addr <= 4'd0;
      write_enable <= 0;
      state <= WAIT;
    end
  end
  ODO_CLR_H: begin
    if (state_prev==ODO_CLR_L) begin
      mem_write <= 16'd0;
      addr <= 4'd1;
      write_enable <= 1;
      state <= TRIP_CLR;
    end else begin 
      mem_write <= 16'd0;
      addr <= 4'd6;
      write_enable <= 1;
      state <= ODO_CLR_L;
    end
  end
  ODO_END: begin
    if (state_prev == ODO_WR_H) begin
      addr <= 4'd0;
      write_enable <= 1;
      if (mem_read[3:0] >= 9) begin
        mem_write <= {2'd0, mem_read[13:4]+10'd1, 4'd0};
      end else begin
        mem_write <= {2'd0, mem_read[13:4], mem_read[3:0]+4'd1};
      end
    end else begin
      mem_write <= 16'd0;
      addr <= 4'd6;
      write_enable <= 0;
    end
    state <= WAIT;
  end
  TRIP_WR: begin
    addr <= 4'd1;
    write_enable <= 1;
    if (mem_read[11:6] >= 59 && mem_read[5:0] >= 59)
      mem_write <= {mem_read[15:12]+4'd1, 12'd0};
    else if (mem_read[5:0] >= 59)
      mem_write <= {mem_read[15:12], mem_read[11:6]+6'd1, 6'd0};
    else
      mem_write <= {mem_read[15:6], mem_read[5:0]+6'd1};
    state <= TRIP_END;
  end
  TRIP_CLR: begin
    if (state_prev==ODO_CLR_H) begin
      addr <= 4'd4;
      write_enable <= 1;
      mem_write <= 16'd0;
      state <= CAL_CLR;
    end else begin
      addr <= 4'd0;
      write_enable <= 1;
      mem_write <= 16'd0;
      state <= ODO_CLR_H;
    end

    /*
    addr <= 4'd6;
    write_enable <= 0;
    mem_write <= 16'd0;
    state <= WAIT;
    */
  end
  TRIP_END: begin
    addr <= 4'd1;
    write_enable <= 0;
    mem_write <= 16'd0;
    state <= WAIT;
  end
  SPEED_WR: begin
    addr <= 4'd2;
    write_enable <= 1;
    mem_write <= 46_080*wheel_config/fork_time;
    state <= SPEED_END;
  end
  SPEED_END: begin
    addr <= 4'd2;
    write_enable <= 0;
    mem_write <= 16'd0;
    state <= WAIT;
  end
  CAD_WR: begin
    addr <= 4'd3;
    write_enable <= 1;
    mem_write <= 76_800_000/crank_time;
    state <= CAD_END;
  end
  CAD_END: begin
    addr <= 4'd3;
    write_enable <= 0;
    mem_write <= 16'd0;
    state <= WAIT;
  end
  WEIGHT_SET: begin
  /*
    addr <= 4'd8;
    write_enable <= 0;
    mem_write <= 16'd0;
    weight <= mem_read[11:8]*100 + mem_read[7:4]*10 + mem_read[3:0];
    state <= WEIGHT_READ;
    */
    addr <= 4'd9;
    write_enable <= 1;
    mem_write <= {2'b00, 2'b10, 4'd1, 4'd7, 4'd5};
    //weight <= mem_read[11:8]*100 + mem_read[7:4]*10 + mem_read[3:0];
    state <= HEIGHT_SET;
  end
  HEIGHT_SET: begin
    addr <= 4'd10;
    write_enable <= 1;
    mem_write <= {6'd0, 1'b1, 1'b1,  4'd2, 4'd3};
    state <= AGE_GENDER_SET;
  end
  AGE_GENDER_SET: begin
  /*
    addr <= 4'd10;
    write_enable <= 0;
    mem_write <= 16'd0;
    state <= USR_END;
    */
    addr <= 4'd8;
    write_enable <= 0;
    mem_write <= 16'd0;
    //weight <= mem_read[11:8]*100 + mem_read[7:4]*10 + mem_read[3:0];
    state <= WEIGHT_READ;
  end
  WEIGHT_READ: begin
  /*
    addr <= 4'd8;
    write_enable <= 0;
    mem_write <= 16'd0;
    weight <= mem_read[11:8]*100 + mem_read[7:4]*10 + mem_read[3:0];
    state <= WEIGHT_READ;
    */
    addr <= 4'd9;
    write_enable <= 0;
    mem_write <= 16'd0;
    weight <= mem_read[11:8]*100 + mem_read[7:4]*10 + mem_read[3:0];
    state <= HEIGHT_READ;
  end
  HEIGHT_READ: begin
    addr <= 4'd10;
    write_enable <= 0;
    mem_write <= 16'd0;
    height <= mem_read[11:8]*100 + mem_read[7:4]*10 + mem_read[3:0];
    state <= AGE_READ;
  end
  AGE_READ: begin
    addr <= 4'd10;
    write_enable <= 0;
    mem_write <= 16'd0;
    age <= mem_read[7:4]*10 + mem_read[3:0];
    state <= USR_END;
    //state <= WHEEL_END;
  end
  USR_W2: begin
    addr <= 4'd8;
    if (incr2) begin
      write_enable <= 1;
      if (mem_read[11:8]<9)
        mem_write <= {2'b0, mem_read[13:12], mem_read[11:8]+4'd1, mem_read[7:0]};
      else
        mem_write <= {2'b0, mem_read[13:12], 4'd0, mem_read[7:0]};
      state <= USR_W2;
    end else if (update) begin
      write_enable <= 1;
      mem_write <= {mem_read[15:14], 2'b01, mem_read[11:0]};
      state <= USR_W1;
    end else begin
      write_enable <= 0;
      state <= USR_W2;
    end
  end
  USR_W1: begin
    addr <= 4'd8;
    if (incr1) begin
      write_enable <= 1;
      if (mem_read[7:4]<9)
        mem_write <= {2'b0, mem_read[13:8], mem_read[7:4]+4'd1, mem_read[3:0]};
      else
        mem_write <= {2'b0, mem_read[13:8], 4'd0, mem_read[3:0]};
      state <= USR_W1;
    end else if (update) begin
      write_enable <= 1;
      mem_write <= {mem_read[15:14], 2'b00, mem_read[11:0]};
      state <= USR_W0;
    end else begin
      write_enable <= 0;
      state <= USR_W1;
    end
  end
  USR_W0: begin
    addr <= 4'd8;
    if (incr0) begin
      write_enable <= 1;
      if (mem_read[3:0]<9)
        mem_write <= {2'b0, mem_read[13:4], mem_read[3:0]+4'd1};
      else
        mem_write <= {2'b0, mem_read[13:4], 4'd0};
      state <= USR_W0;
    end else if (update) begin
      write_enable <= 1;
      mem_write <= {mem_read[15:14], 2'b10, mem_read[11:0]};
      state <= USR_H2;
    end else begin
      write_enable <= 0;
      state <= USR_W0;
    end
  end
  USR_H2: begin
    addr <= 4'd9;
    if (incr2) begin
      write_enable <= 1;
      if (mem_read[11:8]<9)
        mem_write <= {2'b0, mem_read[13:12], mem_read[11:8]+4'd1, mem_read[7:0]};
      else
        mem_write <= {2'b0, mem_read[13:12], 4'd0, mem_read[7:0]};
      state <= USR_H2;
    end else if (update) begin
      write_enable <= 1;
      mem_write <= {mem_read[15:14], 2'b01, mem_read[11:0]};
      state <= USR_H1;
    end else begin
      write_enable <= 0;
      state <= USR_H2;
    end
  end
  USR_H1: begin
    addr <= 4'd9;
    if (incr1) begin
      write_enable <= 1;
      if (mem_read[7:4]<9)
        mem_write <= {2'b0, mem_read[13:8], mem_read[7:4]+4'd1, mem_read[3:0]};
      else
        mem_write <= {2'b0, mem_read[13:8], 4'd0, mem_read[3:0]};
      state <= USR_H1;
    end else if (update) begin
      write_enable <= 1;
      mem_write <= {mem_read[15:14], 2'b00, mem_read[11:0]};
      state <= USR_H0;
    end else begin
      write_enable <= 0;
      state <= USR_H1;
    end
  end
  USR_H0: begin
    addr <= 4'd9;
    if (incr0) begin
      write_enable <= 1;
      if (mem_read[3:0]<9)
        mem_write <= {2'b0, mem_read[13:4], mem_read[3:0]+4'd1};
      else
        mem_write <= {2'b0, mem_read[13:4], 4'd0};
      state <= USR_H0;
    end else if (update) begin
      write_enable <= 1;
      mem_write <= {mem_read[15:14], 2'b10, mem_read[11:0]};
      state <= USR_AGE1;
    end else begin
      write_enable <= 0;
      state <= USR_H0;
    end
  end
  USR_AGE1: begin
    addr <= 4'd10;
    if (incr1) begin
      write_enable <= 1;
      if (mem_read[7:4]<9)
        mem_write <= {2'b0, mem_read[13:8], mem_read[7:4]+4'd1, mem_read[3:0]};
      else
        mem_write <= {2'b0, mem_read[13:8], 4'd0, mem_read[3:0]};
      state <= USR_AGE1;
    end else if (update) begin
      write_enable <= 1;
      mem_write <= {mem_read[15:9], 1'b0, mem_read[7:0]};
      state <= USR_AGE0;
    end else begin
      write_enable <= 0;
      state <= USR_AGE1;
    end
  end
  USR_AGE0: begin
    addr <= 4'd10;
    if (incr0) begin
      write_enable <= 1;
      if (mem_read[3:0]<9)
        mem_write <= {2'b0, mem_read[13:4], mem_read[3:0]+4'd1};
      else
        mem_write <= {2'b0, mem_read[13:4], 4'd0};
      state <= USR_AGE0;
    end else if (update) begin
      write_enable <= 1;
      mem_write <= {mem_read[15:9], 1'b1, mem_read[7:0]};
      state <= USR_GENDER;
    end else begin
      write_enable <= 0;
      state <= USR_AGE0;
    end
  end
  USR_GENDER: begin
    addr <= 4'd10;
    if (incr2) begin
      write_enable <= 1;
      if (!mem_read[9])
        mem_write <= {mem_read[15:10], 1'b1, mem_read[8:0]};
      else
        mem_write <= {mem_read[15:10], 1'b0, mem_read[8:0]};
      state <= USR_GENDER;
    end else if (update) begin
      write_enable <= 0;
      //state <= USR_END;
      addr <= 4'd8;
      mem_write <= 16'd0;
      state <= WEIGHT_READ;
    end else begin
      write_enable <= 0;
      state <= USR_GENDER;
    end
  end
  USR_END: begin
    addr <= 4'd10;
    write_enable <= 0;
    mem_write <= 16'd0;
    if (!mem_read[9])
      BMR <= 10*weight + 625*height/100 - 5*age + 5;
    else
      BMR <= 10*weight + 625*height/100 - 5*age - 161;
    //state <= WAIT;
    state <= CAL_CLR;
  end
  CAL_WR: begin
    addr <= 4'd4;
    write_enable <= 1;
    if (avgSpd < 1609) begin
      mem_write <= (BMR * totalTime * 4) / 8640; 
    end else if (avgSpd < 1915 && avgSpd >= 1609) begin
      mem_write <= (BMR * totalTime * 68) / 86400; 
    end else if (avgSpd < 2237 && avgSpd >= 1915) begin
      mem_write <= (BMR * totalTime * 8) / 8640; 
    end else if (avgSpd < 2559 && avgSpd >= 2237) begin
      mem_write <= (BMR * totalTime * 10) / 8640; 
    end else if (avgSpd < 3058 && avgSpd >= 2559) begin
      mem_write <= (BMR * totalTime * 12) / 8640; 
    end else if (avgSpd >= 3058) begin
      mem_write <= (BMR * totalTime * 158) / 86400; 
    end else begin
      mem_write <= 0; 
    end
    state <= CAL_END;
  end
  CAL_CLR: begin
    if(state_prev==TRIP_CLR) begin
      addr <= 4'd8;
      write_enable <= 1;
      mem_write <= {2'b00, 2'b10, 4'd0, 4'd7, 4'd0};
      state <= WEIGHT_SET;
    end else begin
    /*
      addr <= 4'd6;
      write_enable <= 0;
      mem_write <= 16'd0;
      state <= WAIT;
      */
      addr <= 4'd1;
      write_enable <= 1;
      mem_write <= 16'd0;
      state <= TRIP_CLR;
    end
  end
  CAL_END: begin
    addr <= 4'd4;
    write_enable <= 0;
    mem_write <= 16'd0;
    state <= WAIT;
  end
  AVG_R_T: begin
    addr <= 4'd0;
    write_enable <= 0;
    mem_write <= 16'd0;
    totalTime <= mem_read[15:12]*3600 + mem_read[11:6]*60 + mem_read[5:0];
    state <= AVG_R_DH;
  end
  AVG_R_DH: begin
    addr <= 4'd6;
    write_enable <= 0;
    mem_write <= 16'd0;
    totalDist[31:16] <= mem_read[15:4]*1000 + mem_read[3:0]*100;
    state <= AVG_R_DL;
  end
  AVG_R_DL: begin
    addr <= 4'd5;
    write_enable <= 0;
    mem_write <= 16'd0;
    totalDist[15:0] <= mem_read;
    state <= AVG_WR;
  end
  AVG_WR: begin
    addr <= 4'd5;
    write_enable <= 1;
    mem_write <= 360 * (totalDist[31:16]*100 + totalDist[15:0]) / (totalTime*100);
    state <= AVG_END;
  end
  AVG_END: begin
    addr <= 4'd5;
    write_enable <= 0;
    mem_write <= 16'd0;
    avgSpd <= mem_read;
    state <= WAIT;
  end
  default: state <= WAIT;
  endcase
  
/* case (displayMode) // Change this
  4'd0: // Odometer
    if (clear) begin
      mem_write <= 16'd0;
      addr <= 4'd6;
      write_enable <= 1'b1;
      state <= ODO_CLR_L;
    end else case (state)
      WAIT: begin   ///// MERGE WAIT
        mem_write <= 16'd0;
        addr <= 4'd6;
        write_enable <= 1'b0;
        if (wheelrev_complete) begin /// REPLACE
// if modeUpdate != 4'd0 then update
  //   if (modeUpdate[0])
         // state <= ODO_WR_L;
  //   else if (modeUpdate[1])
        // timer
  // else wait
          state <= ODO_WR_L;
        end else begin
          state <= WAIT;
        end
      end
      ODO_WR_L: begin
        write_enable <= 1'b1;
        addr <= 4'd6;
        if (mem_read >= 10_000) begin
          mem_write <= mem_read - 16'd10_000 + 16'd214;
          state <= ODO_WR_H;
        end else begin
          mem_write <= mem_read + 16'd214;
          state <= ODO_END;
        end
      end
      ODO_WR_H: begin
        mem_write <= 16'd0;
        addr <= 4'd0;
        write_enable <= 1'b0;
        state <= ODO_END;
      end
      ODO_CLR_L: begin
        mem_write <= 16'd0;
        addr <= 4'd0;
        write_enable <= 1'b1;
        state <= ODO_CLR_H;
      end
      ODO_CLR_H: begin
        mem_write <= 16'd0;
        addr <= 4'd6;
        write_enable <= 1'b0;
        state <= WAIT;
		// state <= TRIP_CLR;
      end
      ODO_END: begin
        if (state_prev == ODO_WR_H) begin
          addr <= 4'd0;
          write_enable <= 1'b1;
          if (mem_read[3:0] >= 9)
            mem_write <= {2'd0,mem_read[13:4]+10'd1,4'd0};
          else
            mem_write <= {2'd0,mem_read[13:4],mem_read[3:0]+4'd1};
        end else begin
          mem_write <= 16'd0;
          addr <= 4'd6;
          write_enable <= 1'b0;
        end
        state <= WAIT;
      end
      default: state <= WAIT;
    endcase
  4'd1: // Trip
    if (clear) begin
	  mem_write <= 16'd0;
	  addr <= 4'd1;
	  write_enable <= 1;
	  state <= TRIP_CLR;
	end else case (state)
	// TRIP_WAIT: begin
	  // mem_write <= 16'd0;
	  // addr <= 4'd1;
	  // write_enable <= 0;
	  // if (second_trigger) begin
	    // state <= TRIP_WR;
	  // end else begin 
	    // state <= TRIP_WAIT;
	  // end
	// end
	TRIP_WR: begin
	  addr <= 4'd1;
	  write_enable <= 1;
	  // if (mem_read[11:6] >= 59 && mem_read[5:0] >= 59) begin
	    // mem_write <= {mem_read[15:12]+4'd1, 12'd0};
	  // end else if (mem_read[11:6] >= 59) begin
	  if (mem_read[11:6] >= 59 && mem_read[5:0] >= 59) begin
	    mem_write <= {mem_read[15:12]+4'd1, 12'd0}; 
	  end else if (mem_read[5:0] >= 59) begin
	    mem_write <= {mem_read[15:12], mem_read[11:6]+6'd1, 6'd0};
	  end else begin
	    mem_write <= {mem_read[15:6], mem_read[5:0]+6'd1};
	  end
	  state <= TRIP_END;
	end
	TRIP_CLR: begin
	  addr <= 4'd1;
	  write_enable <= 1;
	  mem_write <= 16'd0;
	  state <= TRIP_END;
	end
	TRIP_END: begin
	  addr <= 4'd1;
	  write_enable <= 0;
	  mem_write <= 16'd0;
	  state <= WAIT;
	end
	endcase
  4'd2: // Speed
    begin
    // if (clear) begin
	  // addr <= 4'd2;
	  // write_enable <= 1;
	  // mem_write <= 16'd0;
	  // state <= SPEED_CLR;
	// end else case (state)
	case (state)
	// SPEED_WAIT: begin
	  // addr <= 4'd2;
	  // write_enable <= 0;
	  // mem_write <= 16'd0;
	  // if (fork_time)
	    // state <= SPEED_WR;
	  // else
	    // state <= SPEED_WAIT;
	// end
	SPEED_WR: begin
	  addr <= 4'd2;
	  write_enable <= 1;
	  // if(mem_read[13:4
	  mem_write <= 46080*wheel_config/fork_time;
	  state <= SPEED_END;
	end
	// SPEED_CLR: begin
	  // addr <= 4'd2;
	  // write_enable <= 1;
	  // mem_write <= 16'd0;
	  // state <= SPEED_END;
	// end
	SPEED_END: begin
	  addr <= 4'd2;
	  write_enable <= 0;
	  mem_write <= 16'd0;
	  state <= WAIT;
	end
	endcase
	end 
  4'd3: // Cadence
    begin
    // if (clear) begin
      // mem_write <= 16'd0;
      // addr <= 4'd3;
      // write_enable <= 1;
      // state <= CAD_WAIT;
    // end else case (state)
	case (state)
    // CAD_WAIT: begin
      // addr <= 4'd3;
	  // write_enable <= 0;
	  // mem_write <= 16'd0;
	  // if (crank_time)
	    // state <= CAD_WR;
	  // else
	    // state <= CAD_WAIT;
    // end
    CAD_WR: begin
      addr <= 4'd3;
	  write_enable <= 1;
	  mem_write <= 76800000/crank_time; 
	  state <= CAD_END;
    end
    // CAD_CLR: begin
      // addr <= 4'd3;
	  // write_enable <= 1;
	  // mem_write <= 16'd0;
	  // state <= CAD_END;
    // end
    CAD_END: begin
      addr <= 4'd3;
	  write_enable <= 0;
	  mem_write <= 16'd0;
	  state <= WAIT;
    end
    endcase
	end
endcase */

  state_prev <= state;
end

endmodule
