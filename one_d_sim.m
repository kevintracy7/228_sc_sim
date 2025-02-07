%% 1d sim 
clear

% Q learning stuff
omega_deg_max = 100;
u_max = 5;
state_space_size = 2*omega_deg_max + 1;
action_space_size = 2*u_max + 1;
Q = zeros(state_space_size,action_space_size);
N = zeros(state_space_size,action_space_size);
gamma = .9;

for kk = 1:100
% timing 
samp_rate = 10;
tf = 100;
t_vec = 0:(1/samp_rate):tf;

% initial conditions 
init = [0 deg2rad(20) 0];

% pre allocate 
x_hist = zeros(3,length(t_vec));






for i = 1:length(t_vec)
    
    % store for plotting 
    x_hist(:,i) = [wrapTo2Pi(init(1));init(2:3)'];
    
    % state at time t
    s_t = discretize_state(rad2deg(init(2)), omega_deg_max);
    %% controller 
    
    % epsilon greedy
    epsilon = .5;
    random_number = rand;
    
    if random_number < epsilon % go with our Q for best action
        [a_t,~] = max_from_Q(Q,s_t);
    else % go with random action
        a_t = randi(action_space_size);
    end
    
    vec = N(s_t,a_t );
    
    if sum(vec>0) == length(vec) % this means i've tried them all 
        [a_t,~] = max_from_Q(Q,s_t);
    end
    
    % update N(s,a) count
    N(s_t,a_t ) = N(s_t,a_t ) + 1;
      
    %% Q learning 
    
    % omega at s_t
    omega_st = init(2); % for the reward function
    
    % input a_t  
    init(3) = u_from_a(a_t,u_max);
    
    u_hist(i) = init(3);
    % sim
    [~,y] = ode45(@spinner_ode,[0 1/samp_rate],init);
    init = y(end,:);
    
    % omega at s_t+1
    omega_stp1 = init(2);
    s_tp1 = discretize_state(rad2deg(init(2)), omega_deg_max);
    
    % reward function 
    r_t = 1e6*(abs(omega_st) - abs(omega_stp1));
    
    % update Q 
    alpha = 1/N(s_t,a_t);
    [~,Q_max_stp1] = max_from_Q(Q,s_tp1);
    Q(s_t,a_t) = Q(s_t,a_t) + alpha*(r_t + gamma*Q_max_stp1 - Q(s_t,a_t));
    
    
end


w_cell{kk} = x_hist(2,:);
end

% figure
% hold on 
% plot(t_vec,x_hist(1,:))
% title('Theta')
% xlabel('Time (s)')
% hold off
% 
% figure
% hold on 
% plot(t_vec,rad2deg(x_hist(2,:)))
% title('Angular Velocity (1D)')
% xlabel('Time (s)')
% ylabel('\omega deg/s')
% hold off

%% animation 


r = 1;
theta = x_hist(1,:);
figure
hold on 
for i = 1:length(theta)
    
    N_R_T = [cos(theta(i)) -sin(theta(i));...
             sin(theta(i))  cos(theta(i))];
    thrust = [0; u_hist(i)];
    
    thrust_N = N_R_T*thrust/15;
    cla
    xlim([-1.4 1.4])
    ylim([-1.2 1.2])
    %axis equal
    
plot([0 r*cos(theta(i))],[0 r*sin(theta(i))],'LineWidth',5)
plot(0, 0, '.', 'MarkerSize', 50)
quiver(r*cos(theta(i)),r*sin(theta(i)),thrust_N(1),thrust_N(2),'LineWidth',3,'MaxHeadSize',5)
pause(.01)
end



%% plot all the runs 

% figure
% hold on 
% plot(t_vec,x_hist(1,:))
% title('Theta')
% xlabel('Time (s)')
% hold off

figure
hold on 
for kk = 1:length(w_cell)
plot(t_vec,rad2deg(w_cell{kk}))
end
title('Angular Velocity (1D)')
legend('Run 1','Run 2','Run 3','Run 4','Run 5')
xlabel('Time (s)')
ylabel('\omega deg/s')
hold off

%% supporting fx


function xdot = spinner_ode(t,x)

% MOI
Izz = 200;

% unpack state
% theta = x(1);
omega = x(2);
u = x(3);

% dynamics
xdot = zeros(size(x));
xdot(1) = omega;  % theta dot
xdot(2) = u/Izz;  % theta double dot 
%xdot(3) = 0 % already specified

end

function s = discretize_state(omega_deg, omega_deg_max)

if abs(round(omega_deg)) > omega_deg_max
    error('outside the state space')
end

s = round(omega_deg) + 1 + omega_deg_max;


end

function a = discretize_action(u, u_max)

if abs(round(u)) > u_max
    error('outside the action space')
end

a = round(u) + 1 + u_max;


end

function u = u_from_a(a,u_max)
% gets control input u from action a
u = a - u_max -1;

end

function init = controller(init,omega_deg_max)
% this was just a test proportional controller 

omega_deg = rad2deg(init(2));

s = discretize_state(omega_deg, omega_deg_max);

% control law 
k = 1;
u = -k*omega_deg;
init(3) = u;



end

function [a,Q_max] = max_from_Q(Q,s)
% returns max Q, and argmax Q for a given state

% row of interest 
vec = Q(s,:);

% maximum Q in the row
Q_max = max(vec);

% find list of actions that produce this Q max
a_list = find(vec == Q_max);

% if there is a tie, or all zeros, choose a random
if length(a_list) > 1
    a = a_list(randi(length(a_list)));
else
    a = a_list(1);
end
end