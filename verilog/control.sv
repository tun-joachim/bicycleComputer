module control (
    input Clock, nReset,
    input [2:0] mode,
    input trip_Reset,
    input wheelsize_menu, wheelsize_digit_change, wheelsize_value_change,
    //output logic [2:0] addr,
    output logic [4:0] displayMode,
    //output logic [3:0] displayMode,
    output logic wheelmenu_trigger, 
    //output logic userProf_trigger,
    output logic clear, update,
    output logic [2:0] incr
);

timeunit 1ns;
timeprecision 100ps;

// state declaration
enum logic [4:0] {ODO, TRIP, SPEED, CADENCE, CALORIE, AVG, DIGIT2, DIGIT1, DIGIT0, MENU_END, WEIGHT2, WEIGHT1, WEIGHT0, HEIGHT2, HEIGHT1, HEIGHT0, AGE1, AGE0, GENDER} state; //, USER_END} state;

// next state logic
always_ff @(posedge Clock, negedge nReset)
  if (!nReset)
    state <= ODO;
  else
    case (state)
      ODO		: if (mode==1) state <= TRIP;
      			  else if (wheelsize_menu) state <= DIGIT2;
      TRIP		: if (mode==2) state <= SPEED;
      			  else if (wheelsize_menu) state <= DIGIT2;
      SPEED		: if (mode==3) state <= CADENCE;
      			  else if (wheelsize_menu) state <= DIGIT2;
      CADENCE		: if (mode==4) state <= CALORIE; //state <= CALORIE;
      			  else if (wheelsize_menu) state <= DIGIT2;
      CALORIE		: if (mode==5) state <= AVG;
      			  else if (wheelsize_menu) state <= DIGIT2;
      AVG		: if (mode==0) state <= ODO;
      			  else if (wheelsize_menu) state <= DIGIT2;
      DIGIT2		: if (wheelsize_digit_change && 
      			      !trip_Reset && 
			      !wheelsize_value_change) state <= DIGIT1;
			  //else if (wheelsize_menu) state <= WEIGHT2;
      DIGIT1		: if (wheelsize_digit_change && 
      			      !trip_Reset && 
			      !wheelsize_value_change) state <= DIGIT0;
      DIGIT0		: if (wheelsize_digit_change && 
      			      !trip_Reset && 
			      !wheelsize_value_change) state <= WEIGHT2; 
			  //state <= MENU_END;
      MENU_END		: state <= ODO;
      WEIGHT2		: if (wheelsize_digit_change && 
      			      !trip_Reset && 
			      !wheelsize_value_change) state <= WEIGHT1;
      WEIGHT1		: if (wheelsize_digit_change && 
      			      !trip_Reset && 
			      !wheelsize_value_change) state <= WEIGHT0;
      WEIGHT0		: if (wheelsize_digit_change && 
      			      !trip_Reset && 
			      !wheelsize_value_change) state <= HEIGHT2;
      HEIGHT2		: if (wheelsize_digit_change && 
      			      !trip_Reset && 
			      !wheelsize_value_change) state <= HEIGHT1;
      HEIGHT1		: if (wheelsize_digit_change && 
      			      !trip_Reset && 
			      !wheelsize_value_change) state <= HEIGHT0;
      HEIGHT0		: if (wheelsize_digit_change && 
      			      !trip_Reset && 
			      !wheelsize_value_change) state <= AGE1;
      AGE1		: if (wheelsize_digit_change && 
      			      !trip_Reset && 
			      !wheelsize_value_change) state <= AGE0;
      AGE0		: if (wheelsize_digit_change && 
      			      !trip_Reset && 
			      !wheelsize_value_change) state <= GENDER;
      GENDER		: if (wheelsize_digit_change && 
      			      !trip_Reset && 
			      !wheelsize_value_change) state <= MENU_END;
			  //state <= USER_END;
      //USER_END		: state <= ODO;
    endcase
			 
// output logic
assign wheelmenu_trigger = wheelsize_menu;

//assign userProf_trigger = state==DIGIT2 && wheelsize_menu;

assign clear = (((state==ODO     && mode!=1) || 
		 (state==TRIP    && mode!=2) || 
		 (state==SPEED   && mode!=3) ||
		 (state==CADENCE && mode!=4) ||
		 (state==CALORIE && mode!=5) ||
		 (state==AVG     && mode!=0)) &&
		 trip_Reset &&
		 !wheelsize_menu);

assign incr[2] = ((state==DIGIT2 || state==WEIGHT2 || 
		   state==HEIGHT2 || state==GENDER) && 
		 wheelsize_value_change && 
		 !wheelsize_digit_change);

assign incr[1] = ((state==DIGIT1 || state==WEIGHT1 || 
		   state==HEIGHT1 || state==AGE1) && 
		 wheelsize_value_change && 
		 !wheelsize_digit_change);

assign incr[0] = ((state==DIGIT0 || state==WEIGHT0 ||
		   state==HEIGHT0 || state==AGE0) &&  
		 wheelsize_value_change && 
		 !wheelsize_digit_change);

//assign addr = (state==ODO) 	   ? 0
//	       : (state==TRIP)	   ? 1
//	       : (state==SPEED)	   ? 2
//	       : (state==CADENCE)  ? 3
//	       : (state==CALORIE)  ? 4
//	       : (state==AVG)  	   ? 5
//	       : (state==DIGIT2 ||
//	          state==DIGIT1 ||
//	          state==DIGIT0)   ? 6
//	    			   : 3'bx;

assign displayMode = (state==ODO ||
		      state==MENU_END) 	? 0
		   : (state==TRIP)	? 1
		   : (state==SPEED)	? 2
		   : (state==CADENCE)	? 3
		   : (state==CALORIE) 	? 4
		   : (state==AVG)	? 5
		   : (state==DIGIT2) 	? 6
		   : (state==DIGIT1) 	? 7
		   : (state==DIGIT0) 	? 8
		   : (state==WEIGHT2)	? 9
		   : (state==WEIGHT1)	? 10
		   : (state==WEIGHT0)	? 11
		   : (state==HEIGHT2)	? 12
		   : (state==HEIGHT1)	? 13
		   : (state==HEIGHT0)	? 14
		   : (state==AGE1)	? 15
		   : (state==AGE0)	? 16
		   : (state==GENDER)	? 17
		   			: 5'bx;
					
assign update = ((state==DIGIT0 || state==DIGIT1 || state==DIGIT2 ||
		  state==WEIGHT0 || state==WEIGHT1 || state==WEIGHT2 ||
		  state==HEIGHT0 || state==HEIGHT1 || state==HEIGHT2 ||
		  state==AGE0 || state==AGE1 || state==GENDER) && 
		  wheelsize_digit_change &&
		  !wheelsize_value_change);


endmodule
