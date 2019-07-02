function out = crossover(in, SELECTION_SIZE, POPULATION_SIZE, NUM_SAMPLES, ZERO_THRESHOLD)
% CROSSOVER Generate children and replace least fit individuals.
% out = output population
% in = input population
% Current algorithm: one-point crossover where the point is within the noise
% threshold for both impulse responses.
    out = in;
    
    for i = (SELECTION_SIZE + 1):POPULATION_SIZE
        parents = randperm(SELECTION_SIZE, 2);
        point = ceil(rand * (NUM_SAMPLES - 1));
        while ~(in(point, parents(1)) < ZERO_THRESHOLD && in(point, parents(2)) < ZERO_THRESHOLD)
            point = ceil(rand * (NUM_SAMPLES - 1));
        end
        
        out(1:point, i) = in(1:point, parents(1));
        out((point + 1):end, i) = in((point + 1):end, parents(2));
    end
end
