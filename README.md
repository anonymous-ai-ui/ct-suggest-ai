# CTSuggest: Clinical Trial Suggestion of Baseline Features using LLM


## Introduction
CTSuggest is a user-friendly application that leverages Large Language Models to generate baseline features for clinical trial design. CTSuggest enables users to specify trial metadata, generate baseline feature suggestions with explanations, and evaluate performance using an "LLM-as-a-Judge" approach. Users can create new trials or use existing trial data from ClinicalTrials.gov. CTSuggest builds upon and improves the LLM prompts developed in the successful CTBench Benchmark (citation redacted for anonymous review). Evaluations using reference baseline features taken from clinical trial publications show that CTSuggest provides suggestions using the state-of-the-art GPT-4o model and the local llama model. CTSuggest is an app for baseline feature generation with explanations available to trial designers. In order to run the github version, one must need an active OpenAI key on line 180 in app.R for the OpenAI models to function. 


    
## Operation Instructions

**Step 1: Specifiy Trial**

   - Fill all specified fields by:
        - Selecting a trial from the dropdown menu under `Choose an NCT ID:` to load it's features and changing them as desired; or
        - Manually entering the fields to your trial specifications.

**Step 2: Generate Descriptors**

   - Click `Generate` to call an LLM to generate a list of baseline descriptors for the specified trial. The output will appear below.
   - Navigate to `Options` to modify the generation options.

**Step 3: Evaluate**

   - Click `Run Evaluation` to call an LLM to compare the list of generated baseline features to the baseline features actually measured in the trial.
   - *Note:* Evaluation is only available when features have been generated for an existing trial

