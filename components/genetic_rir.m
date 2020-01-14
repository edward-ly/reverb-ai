function [irBest, irBestFitness, fitnessCurve, loss] = ...
    genetic_rir(gaParams, irParams, verbose)
% GENETIC_RIR Generates a random impulse response with the given parameters.
%
% Input arguments:
% gaParams = struct containing genetic algorithm parameters
%     POPULATION_SIZE = IR population count
%     SELECTION_SIZE = IR selection count
%     NUM_GENERATIONS = no. of gens
%     PLATEAU_LENGTH = no. of gens before stopping if no new IR found
%     FITNESS_THRESHOLD = fitness value threshold
%     MUTATION_RATE = mutation probability
% irParams = struct containing impulse response parameters
%     SAMPLE_RATE = sample rate of impulse response
%     NUM_SAMPLES = length of recorded impulse response (samples)
%     T60 = T60 decay time (s)
%     ITDG = initial time delay gap (s)
%     EDT = early decay time (s)
%     C80 = clarity (dB)
%     BR = bass ratio
% verbose = print status messages to command window (default: false)
%
% Output arguments:
% irBest = column vector containing the best impulse response
% irBestFitness = fitness value of impulse response returned
% fitnessCurve = column vector recording best fitness values after each
%     generation (optional)
% loss = struct containing error/difference values for each parameter (optional)
%
    % Require IR and GA arguments
    if nargin < 2, error('Not enough input arguments.'); end
    if nargout < 1, error('Not enough output arguments.'); end

    % Set missing input arguments
    if nargin < 3, verbose = false; end

    %-----------------------------------------------------------------------

    % Initialize population
    if verbose, fprintf('Initializing population...\n'); end
    irPopulation = init_pop(gaParams, irParams);
    irFitness = Inf(gaParams.POPULATION_SIZE, 1);
    irBest = zeros(irParams.NUM_SAMPLES, 1);
    irBestFitness = Inf;
    currentGen = 0;
    currentPlatLen = 0;

    if nargout > 2, fitnessCurve = zeros(gaParams.NUM_GENERATIONS + 1, 1); end
    irLoss = repmat(irParams, gaParams.POPULATION_SIZE, 1);

    while true
        % Evaluate population
        for i = 1:gaParams.POPULATION_SIZE
            [irFitness(i), irLoss(i)] = fitness(irPopulation(:, i), irParams);
        end

        % Sort population by fitness value and update best individual
        [irPopulation, irFitness, irLoss] = ...
            sort_pop(irPopulation, irFitness, irLoss);

        if irFitness(1) < irBestFitness
            irBestFitness = irFitness(1);
            irBest = irPopulation(:, 1);
            loss = irLoss(1);
            currentPlatLen = 0;
        else
            currentPlatLen = currentPlatLen + 1;
        end

        % Record best fitness value this generation
        if nargout > 2
            fitnessCurve(currentGen + 1) = irBestFitness;
        end

        if verbose
            fprintf('Generation %d: best fitness value %d\n', ...
                currentGen, irBestFitness);
        end

        % Stop if fitness value is within threshold
        if irBestFitness < gaParams.FITNESS_THRESHOLD
            if verbose, fprintf('Optimal solution found.\n'); end
            break
        end

        % Stop if fitness value is not updated after some number of generations
        if currentPlatLen >= gaParams.PLATEAU_LENGTH
            if verbose, fprintf('Local optimal solution found.\n'); end
            break
        end

        % Go to next generation (or stop if max number of generations reached)
        currentGen = currentGen + 1;
        if currentGen > gaParams.NUM_GENERATIONS
            if verbose, fprintf('Maximum number of generations reached.\n'); end
            break
        end

        % Select best individuals and generate children to replace remaining
        % individuals
        irPopulation = crossover(irPopulation, gaParams.SELECTION_SIZE, ...
            gaParams.POPULATION_SIZE, irParams.NUM_SAMPLES);

        % Mutate entire population
        irPopulation = mutate(irPopulation, gaParams.MUTATION_RATE);
    end
end
