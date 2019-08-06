function out = genetic_rir (SAMPLE_RATE, T60, ITDG, EDT, C80, BR)
%GENETIC_RIR Function equivalent of main.m script for real-time processing.
% out = row vector containing the impulse response
    % Require all arguments
    if nargin < 6, error('Not enough input arguments.'); end

    % Genetic algorithm parameters
    POPULATION_SIZE = 5;
    SELECTION_SIZE = 2;
    NUM_GENERATIONS = 1;
    STOP_GENERATIONS = 1;
    FITNESS_THRESHOLD = 1e-2;
    MUTATION_RATE = 0.001;

    % Impulse response parameters
    NUM_SAMPLES = round(1.5 * T60 * SAMPLE_RATE);

    % Initialize output
    out = zeros(1, 288000);

    %-----------------------------------------------------------------------

    % Initialize population
    irPopulation = init_pop(NUM_SAMPLES, POPULATION_SIZE, SAMPLE_RATE, T60);
    irFitness = Inf(POPULATION_SIZE, 1);
    irBest = zeros(NUM_SAMPLES, 1);
    irBestFitness = Inf;
    currentGen = 0;
    currentStopGen = 0;

    while true
        % Evaluate population
        for i = 1:POPULATION_SIZE
            irFitness(i) = fitness( ...
                irPopulation(:, i), SAMPLE_RATE, T60, ITDG, EDT, C80, BR);
        end

        % Sort population by fitness value and update best individual
        [irPopulation, irFitness] = sort_pop(irPopulation, irFitness);
        if irFitness(1) < irBestFitness
            irBestFitness = irFitness(1);
            irBest = irPopulation(:, 1);
            currentStopGen = 0;
        else
            currentStopGen = currentStopGen + 1;
        end

        % Stop if fitness value is within threshold
        if irBestFitness < FITNESS_THRESHOLD, break; end

        % Stop if fitness value is not updated after some number of generations
        if currentStopGen >= STOP_GENERATIONS, break; end

        % Go to next generation (or stop if max number of generations reached)
        currentGen = currentGen + 1;
        if currentGen > NUM_GENERATIONS, break; end

        % Select best individuals and generate children to replace remaining
        % individuals
        irPopulation = crossover(irPopulation, SELECTION_SIZE, ...
            POPULATION_SIZE, NUM_SAMPLES);

        % Mutate entire population
        irPopulation = mutate(irPopulation, MUTATION_RATE);
    end

    %-----------------------------------------------------------------------
    
    % Transform to row vector
    out(1:NUM_SAMPLES) = irBest';
end