function out = crossover(in, SELECTION_SIZE, POPULATION_SIZE, NUM_SAMPLES)
% CROSSOVER Generate children and replace least fit individuals.
% out = output population
% in = input population
% Current algorithm: one-point crossover where the point is random along the
% length of the impulse response.
    % Require all arguments
    if nargin < 4, error('Not enough input arguments.'); end

    out = in;
    
    for i = (SELECTION_SIZE + 1):POPULATION_SIZE
        parents = randperm(SELECTION_SIZE, 2);
        point = ceil(rand * (NUM_SAMPLES - 1));

        out(1:point, i) = in(1:point, parents(1));
        out((point + 1):end, i) = in((point + 1):end, parents(2));
    end
end
