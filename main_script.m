% Generates an impulse response according to reverb parameters.
% Also applies the impulse response to an audio signal from a WAV file.
% The impulse response and output audio are also saved as WAV files.

% File: main_script.m
% Author: Edward Ly (m5222120@u-aizu.ac.jp)
% Last Updated: 16 June 2019

%% Clear workspace, command window, and figures.
clear; clc; close all;

%% Add paths to any external functions used.
addpath components
addpath utilities

%% Open an audio file for input.
[fileName, filePath] = uigetfile('*.wav', 'Open audio file');
[drySignal, audioSampleRate] = audioread(strcat(filePath, fileName));
[numAudioSamples, numAudioChannels] = size(drySignal);

%% Genetic algorithm parameters.
POPULATION_SIZE = 20;
SELECTION_SIZE = 10;
NUM_GENERATIONS = 20;
FITNESS_THRESHOLD = 1e-4;
MUTATION_RATE = 0.02;

%% User input (reverb fitness) parameters.
T60 = 1;
ITDG = 0.005;
EDT = 0.1;
C80 = 1;
BR = 1.1;

%% Impulse response parameters.
SAMPLE_RATE = audioSampleRate;
NUM_SAMPLES = round((T60 * 1.1) * SAMPLE_RATE);
ZERO_THRESHOLD = 1e-6;
% Only one impulse response channel per individual.
% NUM_CHANNELS = 1;

%% Genetic Algorithm.

% Initialize population.
fprintf("Initializing. Please wait...\n");
irPopulation = init_pop(NUM_SAMPLES, POPULATION_SIZE, SAMPLE_RATE, T60);
irFitness = Inf(POPULATION_SIZE, 1);
irBestFitness = Inf;
currentGen = 0;

fitnessOverTime = zeros(NUM_GENERATIONS + 1, 1);

while true
    % Evaluate population.
    for i = 1:POPULATION_SIZE
        irFitness(i) = fitness( ...
            irPopulation(:, i), SAMPLE_RATE, T60, ITDG, EDT, C80 ...
        );
    end

    % Sort population by fitness value and update best individual.
    [irPopulation, irFitness] = sort_pop(irPopulation, irFitness);
    if irFitness(1) < irBestFitness
        irBestFitness = irFitness(1);
        irBest = irPopulation(:, 1);
    end
    fitnessOverTime(currentGen + 1) = irBestFitness;

    fprintf("Generation %d: best fitness value %d\n", ...
        currentGen, irBestFitness ...
    );

    % Stop if fitness value is within threshold.
    if irBestFitness < FITNESS_THRESHOLD
        fprintf("Found optimal solution.\n");
        break
    end

    % Go to next generation (or stop if max number of generations reached).
    currentGen = currentGen + 1;
    if currentGen > NUM_GENERATIONS
        fprintf("Maximum number of generations reached.\n");
        break
    end

    % Select best individuals and generate children to replace remaining
    % individuals.
    irPopulation = crossover(irPopulation, SELECTION_SIZE, POPULATION_SIZE);
    
    % Mutate entire population.
    irPopulation = mutate(irPopulation, MUTATION_RATE);
end

%% Show impulse response plot.
figure
plot(irBest)
grid on
xlabel('Sample')
ylabel('Amplitude')

%% Show best fitness value over generations.
figure
plot(0:NUM_GENERATIONS, fitnessOverTime)
grid on
xlabel('Generation')
ylabel('Fitness Value')

%% Save best impulse response as audio file.
% Normalize impulse response.
irBest = normalize_signal(irBest, 1);

% Duplicate impulse response to accommodate number of audio channels,
% if necessary.
if numAudioChannels > 1
    irBest = repmat(irBest, 1, numAudioChannels);
end

% Write to WAV file.
audiowrite("output/ir.wav", irBest, SAMPLE_RATE);

%% Apply the impulse response to the input audio signal.

% Add silence to the end of the dry signal with duration equal to duration of
% impulse response (to ensure trailing audio of wet signal doesn't get cut off).
drySignal = cat(1, drySignal, zeros(NUM_SAMPLES, numAudioChannels));

% Apply impulse response to input audio. Each column/channel of the impulse
% response will filter the corresponding column/channel in the audio.
wetSignal = fftfilt(irBest, drySignal);

% Normalize audio.
wetSignal = normalize_signal(wetSignal, 0.99, "all");

% Write to WAV file.
outputFileName = strcat("output/", replace(fileName, ".wav", "_wet.wav"));
audiowrite(outputFileName, wetSignal, SAMPLE_RATE);

%% END OF SCRIPT
fprintf("Done.\n");
