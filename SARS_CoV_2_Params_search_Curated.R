rm(list = ls())

## first set to current directory using setwd
#setwd("C:/....")

## Calling some libraries
library(deSolve)
library(DEoptim)
library(pracma)
library(scales)
library(poweRlaw)
library(RColorBrewer)
library(raster)



################################
# R0 histogram data
################################
R0_data<-vector()   ## https://cmmid.github.io/topics/covid19/overdispersion-from-outbreaksize.html
R0_data[c(seq(1,720,by=1))]=0
R0_data[c(seq(721,800,by=1))]=1
R0_data[c(seq(801,835,by=1))]=2
R0_data[c(seq(836,860,by=1))]=3
R0_data[c(seq(861,880,by=1))]=4
R0_data[c(seq(881,895,by=1))]=5
R0_data[c(seq(896,905,by=1))]=6
R0_data[c(seq(906,910,by=1))]=7
R0_data[c(seq(911,913,by=1))]=8
R0_data[c(seq(914,916,by=1))]=9
R0_data[c(seq(917,919,by=1))]=10
R0_data[c(seq(920,940,by=1))]=15
R0_data[c(seq(941,1000,by=1))]=25


################################
# Serial Interval histogram data
################################

SI_data<-vector()  # PMID: 32191173
SI_data[c(seq(1,1,by=1))]=-8
SI_data[c(seq(2,2,by=1))]=-5
SI_data[c(seq(3,5,by=1))]=-4
SI_data[c(seq(6,6,by=1))]=-3
SI_data[c(seq(7,7,by=1))]=-2
SI_data[c(seq(8,8+7,by=1))]=0
SI_data[c(seq(16,16+6,by=1))]=1
SI_data[c(seq(23,23+9,by=1))]=2
SI_data[c(seq(33,33+13,by=1))]=3
SI_data[c(seq(47,47+7,by=1))]=4
SI_data[c(seq(55,55+11,by=1))]=5
SI_data[c(seq(67,67+7,by=1))]=6
SI_data[c(seq(75,80,by=1))]=7
SI_data[c(seq(81,87,by=1))]=8
SI_data[c(seq(88,92,by=1))]=9
SI_data[c(seq(93,96,by=1))]=10
SI_data[c(seq(97,99,by=1))]=11
SI_data[c(seq(100,102,by=1))]=12
SI_data[c(seq(103,105,by=1))]=13
SI_data[c(seq(106,106,by=1))]=14
SI_data[c(seq(107,107,by=1))]=15
SI_data[c(seq(108,108,by=1))]=16
SI_data[c(seq(109,109,by=1))]=16

################################
# in vitro probability of positive virus culture data https://www.medrxiv.org/content/10.1101/2020.06.08.20125310v1
################################

VL_NTH<- c(seq(4,10,by=0.5))
PROB_NTH<- c(0, 0, 0, 0, 0.02, 0.05, 0.1, 0.2, 0.32, 0.5, 0.67, 0.8, 0.88)

################################
# Within host viral dynamics ODE model
################################

SARS_COV_model <- function(t,x,params){
  with(as.list(x),{   
    
    ddt_S = -beta*V*S
    ddt_I = beta*V*S - delta*I^k*I - m*E^r*I/(E^r+E50^r) 
    ddt_V = p*I-c*V
    
    ddt_M1 = w*I*M1 - q*M1
    ddt_M2 = q*(M1-M2)
    ddt_E = q*M2- de*E
    
    der <- c(ddt_S,ddt_I,ddt_V,ddt_E,ddt_M1,ddt_M2)
    
    list(der)
  })       
}


################################   
# Define area under curve (AUC) calculation function
################################  
AUC <- function(t,y) {
  y1=na.omit(y)
  mn=length(y1)
  val_AUC=(trapz(t[seq(1,mn,by=1)],na.omit(y)))
  return(val_AUC)
}

################################
# Main
################################


################################
# 1. Read parameters for within host model
################################

Parameters = read.csv("SimulatedParameters.txt",header=TRUE)

########################################################
########################################################

#### choose parameter options for "rho" -- or provide a vector
dispersion_options<- c(10) 

#### choose parameter options/value for "tau" or provide a vector
tzero_options=c(1)

#### choose parameter options/value for "alpha" or provide a vector 
alpha_options=c(2)

#### choose parameter options/value for "lambda" or provide a vector
AUC_factor_options<- c(4) ## lambda is 10^AUC_factor

####choose parameter options/value for "theta" or provide a vector
no_contact_options=c(4)


############# Define output matrix
PAR_proj_R0_SI = matrix(0,nrow=length(tzero_options)*length(alpha_options)*length(AUC_factor_options)*length(no_contact_options)*length(dispersion_options),ncol=15)
colnames(PAR_proj_R0_SI)=c("tzero","alpha","betat","no_contact","dispersion","R0","STD_R0","SI","STD_SI","GT","STD_GT","R0_asym_infections","RSS_dispersion","RSS_doseresponse","No_simulation")

par_ind=1

for (dispersion in seq(1,length(dispersion_options),by=1)) { 

ity=1

for (tzero_mean in tzero_options) { 
  
  ij=1
  
  for (alpha in alpha_options){ 
    
    ik=1
    
    for (AUC_factor in AUC_factor_options){
      
      ix=1
      
      
      for (no_contact_per_day in no_contact_options) {

        max_simulation=1000 ### We simulate each parameter combination for 1000 transmitters
        
        first_loop=seq(1,max_simulation,by=1)  ### creating a loop for 1000 transmitters
        
        ijx=1
        
        R0_infections<- vector()
        R0_asym_infections<- vector()
        SI_infections<- vector()
        GT_infections<- vector()
        presymptomatic_incidence<- vector()
        symptomatic_incidence<- vector()
        asymptomatic_incidence<-vector()
        
        for (yu in first_loop){  ## running the loop for 1000 transmitters

          mtp=raster::sampleInt(10^4, 1, replace = FALSE) ## randomly picking a row for within parameters; alternative option: replace = TRUE
            
          ## parameters for the within host model 
          beta=Parameters$beta[mtp]
          delta=Parameters$delta[mtp]
          k=Parameters$k[mtp]
          p=Parameters$p[mtp]
          m=Parameters$m[mtp]
          w=Parameters$w[mtp]
          E50=Parameters$E50[mtp]
          r=Parameters$r[mtp]
          q=Parameters$q[mtp]
          de=Parameters$de[mtp]
          c=Parameters$c[mtp]
          tzero= tzero_mean
          
          # Initial conditions for the within-host model
          S_0 = 1e7
          I_0 = 1
          V_0 = p*I_0/c
          E_0 = 0
          M1_0 = 1
          M2_0 = 0
          
          dT=1 # Sampling frequency in days ; this should be less than 1 -- noted only rho will change with change in dT as rho_final = rho_paper/dT
          
          ## The incubation period (time from exposure to symtptoms) is gamma distributed -- an incubation period with a mean of 6.4 and SD of 2.3 days [4], and a mean of 4.8 and a SD 2.6 days [7]  --- https://www.ncbi.nlm.nih.gov/pmc/articles/PMC7201952/
          mean_incubation_period=5.2 # mean from https://www.acpjournals.org/doi/10.7326/M20-0504 and https://www.ncbi.nlm.nih.gov/pmc/articles/PMC7201952/
          std_incubation_period=2.8 # days --  https://www.ncbi.nlm.nih.gov/pmc/articles/PMC7201952/
          incubation_period_infector=pmax(0,rgamma(n = 1, shape = 3.45,
                                                   scale=(1/0.66))) # rate=0.66, https://www.ncbi.nlm.nih.gov/pmc/articles/PMC7201952/
          

          Non_replication_phase_duration_infector=tzero ### this is the time duration in which infector has not established one infected cell
          
          #### For exposed contacts or infectee
          tzero2=tzero_mean   # rnorm(1, mean = tzero_mean, sd=0.001)
          
          incubation_period_infectee=pmax(0,rgamma(n = 1, shape = 3.45,
                                                   scale=(1/0.66))) # rate=0.66, https://www.ncbi.nlm.nih.gov/pmc/articles/PMC7201952/
          
        
          Non_replication_phase_duration_infectee=tzero2### this is the time duration in which infectee has not established one infected cell
          
    
          ########################################################################
          ################## Checking if transmission can occur in the phase when infector has not established one infected cell
          ########################################################################
          
          Non_replication_phase_duration_infector_round=round(Non_replication_phase_duration_infector) ### rounding to allow discretization 

          Non_replication_phase_duration_infector_round_discrete=c(seq(0,Non_replication_phase_duration_infector_round,by=dT))
          ### Viral loads before the first infected cell was assumed to be V_0 
          V_asym=rep((V_0),length(Non_replication_phase_duration_infector_round_discrete))
          
          ### calculating infectiouesness based on VL
          Prob_V_asym=(pmax(0,(V_asym)))^alpha/((10^AUC_factor)^alpha   +   (pmax(0,(V_asym)))^alpha)
          
          ####### sampling number of exposed contacts at pre-specificed time points 
          no_contact_per_day_options<-c()
          no_contact_per_day_options=rgamma(n = length(Non_replication_phase_duration_infector_round_discrete), shape = (no_contact_per_day/dispersion_options[dispersion]),
                                            scale=dispersion_options[dispersion]) # Random variable X is distributed X=gamma(A,B) with mean =AB 
          
          ## check for successful transmissions (since infectiousness / transmission risk is not successful transmission)
          ### to evaluate successful transmission event by comparing Infectiousness with a random number between 0 and 1
          random_numbers_asym= runif(n=length(Prob_V_asym),min=0,max=1)  # uniform distribution on the interval from min to max.
          number_of_new_infections_ideal_case_asym=dT*no_contact_per_day_options*Prob_V_asym
          number_of_new_infections_actual_asym=dT*no_contact_per_day_options[Prob_V_asym>random_numbers_asym]*Prob_V_asym[Prob_V_asym>random_numbers_asym]
          time_new_infections_actual_asym=Non_replication_phase_duration_infector_round_discrete[Prob_V_asym>random_numbers_asym]
          
          R0_asym_infections[ijx]=round(sum(number_of_new_infections_actual_asym))
          asymptomatic_incidence[ijx]=round(sum(number_of_new_infections_actual_asym))
          
          
          if(R0_asym_infections[ijx]>0){  ### if infector started spreading infection in this unlikely phase, for some really weird parameter combinations
            
            #print("if infector started spreading infection in this unlikely phase before there is even one infected cell")
            
            ##### Now we simulate viral dynamics for period after viral load kicks off with one infected cell
            init.x <- c(S=S_0,I=I_0,V=V_0,E=E_0,M1=M1_0,M2=M2_0)
            t.out <- seq(tzero,tzero+30,by=dT)
            params=c()
            out <- as.data.frame(lsodar(init.x,t.out,SARS_COV_model,params))
            out$V[out$time>tzero+20]=0 ## assumption that viral loads persists on average 20 days
 
            Prob_V=(pmax(0,(out$V)))^alpha/((10^AUC_factor)^alpha   +   (pmax(0,(out$V)))^alpha) ### defining infectiousness according to viral loads
            
            time_V_final=t.out[is.finite(Prob_V)] ## getting rid of any NANs
            Prob_V_final=Prob_V[is.finite(Prob_V)]## getting rid of any NANs
            
            V_final=(out$V[is.finite(Prob_V)]) ## Viral loads after getting rid of any NANs
            
            no_contact_per_day_options_mid<-c()
            no_contact_per_day_options_mid=rgamma(n = length(t.out), shape = (no_contact_per_day/dispersion_options[dispersion]),
                                                  scale=dispersion_options[dispersion]) # Random variable X is distributed X=gamma(A,B) with mean =AB 
            
            no_contact_per_day_options<-c()
            no_contact_per_day_options=no_contact_per_day_options_mid[seq(1,length(Prob_V_final),by=1)] ## exposed contacts sampled only at those time poins where there are no NANs in viral laods
            
            random_numbers= runif(n=length(Prob_V_final),min=0,max=1)  # uniform distribution on the interval from min to max.
            number_of_new_infections_ideal_case=dT*no_contact_per_day_options*Prob_V_final
            number_of_new_infections_actual=dT*no_contact_per_day_options[Prob_V_final>random_numbers]*Prob_V_final[Prob_V_final>random_numbers]
            time_new_infections_actual=time_V_final[Prob_V_final>random_numbers]
            
            if(length(number_of_new_infections_actual)>0  && sum(number_of_new_infections_actual)>0.5){
              
              total_number_of_new_infections<- vector() # the addition is done to avoid classify 10^-6 as new infection and only looking at integers for the number of secondary transmissions; this assumption plays out evenly due to large number (1000) transmitters
              ks_options=seq(1,length(number_of_new_infections_actual),by=1)
              for (ks in ks_options) {
                if(ks==1){ 
                  total_number_of_new_infections[ks]=number_of_new_infections_actual[ks]
                } else {
                  total_number_of_new_infections[ks]=number_of_new_infections_actual[ks]+total_number_of_new_infections[ks-1] 
                }
                
              }
   
              total_number_of_new_infections=round(total_number_of_new_infections) ### because non-integer number of secondary transmissions from a transmitter do not make sense
            }
            
            R0_infections[ijx]=max(total_number_of_new_infections) + R0_asym_infections[ijx] ### recording Individual reproduction number
            GT_infections[ijx]=time_new_infections_actual_asym[1] ### getting generation time
            
            time_from_infection_to_symptoms_infector=incubation_period_infector
            time_from_infection_to_symptoms_infectee=incubation_period_infectee
            
            SI_infections[ijx]=round(time_new_infections_actual_asym[1]    ### recording Serial Interval
                                     +time_from_infection_to_symptoms_infectee
                                     -time_from_infection_to_symptoms_infector)
            
            ########################################################################
          }  else { ###  infector does not spread infection in that unlikely phase and only start spreading after VL replication kicks off
            
            
            #print("infector does not spread infection in unlikely phase")
            ### we more of less repeat the same thing that we did earlier
            
            init.x <- c(S=S_0,I=I_0,V=V_0,E=E_0,M1=M1_0,M2=M2_0)
            t.out <- seq(tzero,tzero+30,by=dT)
  
            params=c()
            out <- as.data.frame(lsodar(init.x,t.out,SARS_COV_model,params))
            out$V[out$time>tzero+20]=0
            
            Prob_V=(pmax(0,(out$V)))^alpha/((10^AUC_factor)^alpha   +   (pmax(0,(out$V)))^alpha)
            
            time_V_final=t.out[is.finite(Prob_V)]
            Prob_V_final=Prob_V[is.finite(Prob_V)]
            
            V_final=(out$V[is.finite(Prob_V)])
            
            no_contact_per_day_options_mid<-c()
            no_contact_per_day_options_mid=rgamma(n = length(t.out), shape = (no_contact_per_day/dispersion_options[dispersion]),
                                                  scale=dispersion_options[dispersion]) # Random variable X is distributed X=gamma(A,B) with mean =AB 
            
            no_contact_per_day_options<-c()
            no_contact_per_day_options=no_contact_per_day_options_mid[seq(1,length(Prob_V_final),by=1)]
            
            random_numbers= runif(n=length(Prob_V_final),min=0,max=1)  # uniform distribution on the interval from min to max.
            number_of_new_infections_ideal_case=dT*no_contact_per_day_options*Prob_V_final
            as=Prob_V_final>random_numbers

            number_of_new_infections_actual=dT*no_contact_per_day_options[as]*Prob_V_final[as]
            time_new_infections_actual=time_V_final[as]

            if(length(number_of_new_infections_actual)>0  && sum(number_of_new_infections_actual)>0.5){ ## done to not run a computatioanlly expensive for loop in case tehre are no secondary transmissions
              
              total_number_of_new_infections<- vector() 
              ks_options=seq(1,length(number_of_new_infections_actual),by=1)
              for (ks in ks_options) {
                if(ks==1){ 
                  total_number_of_new_infections[ks]=number_of_new_infections_actual[ks]
                } else {
                  total_number_of_new_infections[ks]=number_of_new_infections_actual[ks]+total_number_of_new_infections[ks-1] 
                }
                
              }

              total_number_of_new_infections=round(total_number_of_new_infections)

              ### to get times when number infections happen 
              time_new_infections_actual_after_randomization=time_new_infections_actual[total_number_of_new_infections>0]
              total_number_of_new_infections=total_number_of_new_infections[total_number_of_new_infections>0]
              
              
              #### to obtain indexes of when new infections occur by eliminating repetitions 
              index_where_new_infections_happen=match(unique(total_number_of_new_infections),total_number_of_new_infections)
              
              ############################ We record the time of the secondary transmission
              time_when_new_infection_is_added=time_new_infections_actual_after_randomization[index_where_new_infections_happen]  

              ############################ We can record the time of the secondary transmission relative to tzero, the time at which VL kicks off with one infected cells
              time_when_new_infection_is_added_relative_to_tzero=time_when_new_infection_is_added  # +tzero  
              
              cumulative_incidence_temp=total_number_of_new_infections[index_where_new_infections_happen] ### this is cumulative incidence 
            
              
              ###  We calculate incidence based on cumulative incidence at every dT time step
              incidence<-vector()
              y_length=seq(1,length(cumulative_incidence_temp),by=1)
              for (yid in y_length){
                if(yid==1){
                  incidence[yid]=cumulative_incidence_temp[yid]
                } else{
                  incidence[yid]=cumulative_incidence_temp[yid]-cumulative_incidence_temp[yid-1]  ################ this is imp
                }
              }
              
              
              #### To check if secondary infection is presymptomatic vs symptomatic 
              ind_presympt = which(time_when_new_infection_is_added+tzero-incubation_period_infector<=0)
              presymptomatic_incidence[ijx]=sum(incidence[ind_presympt])   ################ this is imp
              
              ind_sympt = which(time_when_new_infection_is_added+tzero-incubation_period_infector>0)    ################ this is imp
              symptomatic_incidence[ijx]=sum(incidence[ind_sympt])

              #### Determine individual reproduction number
              R0_infections[ijx] = sum(incidence)
              
              #################### record individual R0, SI and GT 

              if(isempty(incidence)){
                SI_infections[ijx]= NA # maximum time period if no new infections happen
                R0_infections[ijx]=0
                GT_infections[ijx]=NA

                
              } else{
              
                R0_infections[ijx] = sum(incidence)

                time_from_infection_to_VL_kick_off_infector=Non_replication_phase_duration_infector
                time_from_VL_kick_off_infector_to_secondary_infection= time_when_new_infection_is_added[1] 
                
                GT_infections[ijx]=round(time_from_infection_to_VL_kick_off_infector
                                         +time_from_VL_kick_off_infector_to_secondary_infection)
                
                time_from_infection_to_symptoms_infector=incubation_period_infector
                time_from_infection_to_symptoms_infectee=incubation_period_infectee
                
                SI_infections[ijx]=round(time_from_infection_to_VL_kick_off_infector
                                         +time_from_VL_kick_off_infector_to_secondary_infection
                                         +time_from_infection_to_symptoms_infectee
                                         -time_from_infection_to_symptoms_infector)
 
              }
              
            }  else { ### this checks whether infections happened at all or not
              SI_infections[ijx]= NA
              R0_infections[ijx]=0
              GT_infections[ijx]=NA
              
              
            } 
            
            ijx=ijx+1  ## increasing counter
          
          } 
          
        }   
        
        

        alphat=alpha
        
        betat=round(log10(10^AUC_factor),digits=1)

        no_contact=no_contact_per_day
        
        R0=mean(R0_infections,na.rm=TRUE)
        std_R0=std(R0_infections)
        
        ############ R0 histogram data to compare against
        R0_standard <-c (0.72, 0.08, 0.035, 0.025, 0.020, 0.015, 0.010, 0.005, 0.004,0.003, 1-0.917 )  
        ############
        
        
        
        ############ Simulated R0 histogram data
        ct<-vector()
        ct[1]= length(which(R0_infections==0))/max_simulation
        ct[2]= length(which(R0_infections==1))/max_simulation
        ct[3]= length(which(R0_infections==2))/max_simulation
        ct[4]= length(which(R0_infections==3))/max_simulation
        ct[5]= length(which(R0_infections==4))/max_simulation
        ct[6]= length(which(R0_infections==5))/max_simulation
        ct[7]= length(which(R0_infections==6))/max_simulation
        ct[8]= length(which(R0_infections==7))/max_simulation
        ct[9]= length(which(R0_infections==8))/max_simulation
        ct[10]= length(which(R0_infections==9))/max_simulation
        ct[11]= length(which(R0_infections>=10))/max_simulation
        
        
        RSS_dispersion_R0=   sqrt(sum((ct - R0_standard)^2)) ### This error provides an estimated of how well our model does in reproducitn the R0 histogram
        ############        

        
        SI_infections=na.omit(SI_infections)
        #print(SI_infections)
        if(length(SI_infections)==0){
          SI=0
          std_SI=0
        } else { 
          SI=mean(SI_infections,na.rm=TRUE)
          std_SI=std(SI_infections)
        }
        
        GT_infections=na.omit(GT_infections)
        #print(GT_infections)
        if(length(GT_infections)==0){
          GT=0
          std_GT=0
        } else { 
          GT=mean(GT_infections,na.rm=TRUE)
          std_GT=std(GT_infections)
        }
        
        RSS_doseresponse=1 # ignore this please
        
        print(c(R0,SI,GT))

        PAR_proj_R0_SI[par_ind,]=c(tzero_mean,alphat,betat,no_contact,dispersion_options[dispersion],R0,std_R0,SI,std_SI,GT,std_GT,mean(R0_asym_infections),RSS_dispersion_R0,RSS_doseresponse,max_simulation)
        
        
        write.csv(PAR_proj_R0_SI,file="Output_File_search.csv",row.names = FALSE) 
        
        
        ix=ix+1
        par_ind=par_ind+1
      
        
      }   ## third loop (no contacts)
      
      ik=ik+1
      
    } ## second  lopp  (AUC factor, lambda)
    
    ij=ij+1
  }  # first loop (alpha)

  ity=ity+1
  
} # tzero (tau) loop

} # dispersion (rho) loop
                 




################################### Criteria to find a suitable parameter combination 
RN_min=1.4 
RN_max=2.5
SI_min=4
SI_max=4.5

Proj_COVID_R0=read.csv(file="Output_File_search.csv",as.is=TRUE)

Proj_COVID_R0=data.frame(Proj_COVID_R0)

Proj_COVID_R0$alpha=as.numeric(Proj_COVID_R0$alpha)

Proj_COVID_R0$R0=as.numeric(Proj_COVID_R0$R0)

Proj_COVID_R0$SI=as.numeric(Proj_COVID_R0$SI)

Proj_COVID_R0_alpha=filter(Proj_COVID_R0,between(R0,RN_min,RN_max),between(SI,SI_min,SI_max),
                           RSS_dispersion<0.05) 
print(Proj_COVID_R0_alpha) ## these will be the combinations, and we select the one with the lowest RSS_dispersion

