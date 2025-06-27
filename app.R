# CTSuggest App
# Rev: 20 Mar 2025 (TL fixes reference and three-shot)
# 

library(dplyr)
library(DT)
library(shiny)
library(openai) # devtools::install_github("irudnyts/openai", ref = "r6")
library(jsonlite)
library(RCurl)
library(rlist)
library(tidyr)
library(stringr)
library(purrr)
library(bslib)
library(shinyjs)

# What version of CTSuggest?
version <- read.csv("version.csv")$date

# Default prompt text
systemPromptText.default <- "You are a helpful assistant with expertise in the clinical domain and clinical trial design. You will be asked queries related to clinical trials, each marked by a '##Question' heading.
Within these queries, you will find comprehensive details about a clinical trial, structured within specific subsections denoted by '<>' tags. These subsections include critical information such as:
- **Title**: The official name of the trial.
- **Brief Summary**: A concise description of the trial’s objectives and methods.
- **Condition**: The medical condition or disease under study.
- **Inclusion and Exclusion Criteria**: Eligibility requirements for participants.
- **Intervention**: The treatment, procedure, or action being studied.
- **Outcomes**: The measures used to evaluate the effect of the intervention.
Your task is to provide a list of probable baseline features of the clinical trial. Baseline features are demographic or clinical characteristics assessed at baseline that are used to analyze the primary outcome measures, characterize the study population, and validate findings. Examples include age, sex, BMI, blood pressure, disease severity, smoking status, and medication history.
Respond only with the list of baseline features in the format:  
{feature 1, feature 2, feature 3, ...}.  
**Guidelines**:
1. **Avoid Explanations**: Do not provide any additional text, explanations, or context.
2. **No Tags or Headers**: Do not include any tags, headings, or formatting other than the list itself.
3. **Avoid Repetition**: Ensure each baseline feature appears only once in the list.
For example:  
If the query specifies a clinical trial on hypertension, your response might look like:  
{age, sex, BMI, blood pressure, smoking status, medication history}
Now evaluate the query provided under the '##Question' heading and generate your response.
**Then, provide detailed explanations for each selected baseline feature, linking them directly to the study’s objectives or hypotheses. For instance, explain how age and gender are related to the condition under study, supported by data or literature indicating their relevance. Also, note any statistical models or analyses that demonstrate the impact of these demographics on the study's outcomes.**
"

systemPromptText_Three_shot.default <- "You are a helpful assistant with expertise in the clinical domain and clinical trial design. You will be asked queries related to clinical trials, each marked by a '##Question' heading.
Within these queries, you will find comprehensive details about a clinical trial, structured within specific subsections denoted by '<>' tags. These subsections include critical information such as:
- **Title**: The official name of the trial.
- **Brief Summary**: A concise description of the trial’s objectives and methods.
- **Condition**: The medical condition or disease under study.
- **Inclusion and Exclusion Criteria**: Eligibility requirements for participants.
- **Intervention**: The treatment, procedure, or action being studied.
- **Outcomes**: The measures used to evaluate the effect of the intervention.
Your task is to provide a list of probable baseline features of the clinical trial. Baseline features are demographic or clinical characteristics assessed at baseline that are used to analyze the primary outcome measures, characterize the study population, and validate findings. Examples include age, sex, BMI, blood pressure, disease severity, smoking status, and medication history.
Respond only with the list of baseline features in the format:  
{feature 1, feature 2, feature 3, ...}
You will be given three examples for reference. Follow the same pattern for your responses.
**Guidelines**:
1. **Avoid Explanations**: Do not provide any additional text, explanations, or context.
2. **No Tags or Headers**: Do not include any tags, headings, or formatting other than the list itself. 
3. **Avoid Repetition**: Ensure each baseline feature appears only once in the list.
---
### **Example 1**
##Question:  
**Title**: <Insert trial title>  
**Brief Summary**: <Insert trial summary>  
**Condition**: <Insert condition>  
**Inclusion and Exclusion Criteria**: <Insert criteria>  
**Intervention**: <Insert intervention>  
**Outcomes**: <Insert outcomes>
##Answer:  
{feature 1, feature 2, feature 3, feature 4, feature 5, ...}
---
### **Example 2**
##Question:  
**Title**: <Insert trial title>  
**Brief Summary**: <Insert trial summary>  
**Condition**: <Insert condition>  
**Inclusion and Exclusion Criteria**: <Insert criteria>  
**Intervention**: <Insert intervention>  
**Outcomes**: <Insert outcomes>
##Answer:  
{feature 1, feature 2, feature 3, feature 4, feature 5, feature 6, ...}
---
### **Example 3**
##Question:  
**Title**: <Insert trial title>  
**Brief Summary**: <Insert trial summary>  
**Condition**: <Insert condition>  
**Inclusion and Exclusion Criteria**: <Insert criteria>  
**Intervention**: <Insert intervention>  
**Outcomes**: <Insert outcomes>
##Answer:  
{feature 1, feature 2, feature 3, feature 4, ...}
---
Now evaluate the next query provided under the '##Question' heading and respond in the same format as the examples.
**Then, provide detailed explanations for each selected baseline feature, linking them directly to the study’s objectives or hypotheses. For instance, explain how age and gender are related to the condition under study, supported by data or literature indicating their relevance. Also, note any statistical models or analyses that demonstrate the impact of these demographics on the study's outcomes.**
"
systemPromptText_Evaluation.gpt <- "
    You are an expert assistant in the medical domain and clinical trial design. You are provided with details of a clinical trial.
    Your task is to determine which candidate baseline features match any feature in a reference baseline feature list for that trial. 
    You need to consider the context and semantics while matching the features.

    For each candidate feature:   
    
        1. Identify a matching reference feature based on similarity in context and semantics.
        2. Remember the matched pair.
        3. A reference feature can only be matched to one candidate feature and cannot be further considered for any consecutive matches.
        4. If there are multiple possible matches (i.e. one reference feature can be matched to multiple candidate features or vice versa), choose the most contextually similar one.
        5. Also keep track of which reference and candidate features remain unmatched.
    6. DO NOT provide the code to accomplish this and ONLY respond with the following JSON. Perform the matching yourself.
    Once the matching is complete, omitting explanations provide the answer only in the following form:
  {\"matched_features\": [[\"<reference feature 1>\" , \"<candidate feature 1>\" ],[\"<reference feature 2>\" , \"<candidate feature 2>\"]],\"remaining_reference_features\": [\"<unmatched reference feature 1>\" ,\"<unmatched reference feature 2>\"],\"remaining_candidate_features\" : [\"<unmatched candidate feature 1>\" ,\"<unmatched candidate feature 2>\"]}
  7. Please generate a valid JSON object, ensuring it fits within a single JSON code block, with all keys and values properly quoted and all elements closed. Do not include line breaks within array elements."


systemPromptText_Evaluation.llama <- "
You are an expert assistant in the medical domain and clinical trial design. You have a reference baseline feature list and a candidate baseline feature list. Your task is to match each candidate feature to a reference feature by focusing deeply on semantics, medical similarity, and context. This includes recognizing synonyms, near-synonyms, or slightly varied medical terminology that refer to the same concept.
**Instructions**:
1. If a candidate feature and a reference feature have the same or very similar medical meaning, consider them a match.
2. Each reference feature can be used only once. After matching it to a candidate feature, do not match it again.
3. If multiple candidate features might match a single reference feature, pick the candidate that is closest in meaning.
4. Each candidate feature can also be matched only once. 
5. Any features not matched by the end should remain in the \"remaining_reference_features\" or \"remaining_candidate_features\" arrays.
Once the matching is complete, omitting explanations provide the answer only in the following form:
{\"matched_features\": [[\"<reference feature 1>\" , \"<candidate feature 1>\" ],[\"<reference feature 2>\" , 
  \"<candidate feature 2>\"]],\"remaining_reference_features\": [\"<unmatched reference feature 1>\" ,\"<unmatched 
  reference feature 2>\"],\"remaining_candidate_features\" : [\"<unmatched candidate feature 1>\" ,\"<unmatched 
  candidate feature 2>\"]} 
  For example - {\"matched_features\": [[\"<Age>\", \"<age>\" ], [\"<Sex>\", \"<sex>\" ]]}...
**Critical Requirements**:
- Return no additional text, code blocks, or explanations. Only the JSON object.
- Do not add or rename keys. 
- Do not use line breaks inside array elements.
- If no matches exist, use an empty array for \"matched_features\".
Perform the matching yourself, focusing carefully on semantics and medical terminology.
"

title.default <- ""
brief_summary.default <- ""
condition.default <- ""
eligibility.default <- ""
intervention.default <- ""
outcome.default <- ""

# Assign Inclusion and Exclusion Criteria
split_criteria <- strsplit(eligibility.default, "Exclusion Criteria:\n")[[1]]
Inclusion_Criteria <- gsub("Inclusion Criteria:\n", "", split_criteria[1])
Exclusion_Criteria <- split_criteria[2]
actual_features.default <- "`Age`, `Duration of OA`, `Kellgren-Lawrence Classification`, `Coexisting Disease`, `BMI`, `WOMAC Function`, `WOMAC Stiffness`, `WOMAC Pain`, `WIQ Total Score`, `SF-36 Physical Composite Score`, `6 Minute Walk`, `3-Minute Walk Stair Climb And Descend`, "

resultText.debug <- "OpenAI API result here..."

# Base URL for WD endpoint
# This actually retrieves JSON!
wd.base.url <- "https://www.wikidata.org/w/api.php?action=wbgetentities&sites=enwiki&props=descriptions&languages=en&format=json&normalize="
wd.search.base.url <- "https://www.wikidata.org/w/api.php?action=wbsearchentities&language=en&props=&format=json"

# Pretty link-creating function
createWebLink <- function(val) {
  if (grepl("http://", val)) {
    sprintf('<a href="%s" target="_blank" title="Click to open page in new tab">%s</a>',val,val)
  } else if (grepl("https://", val)) {
    sprintf('<a href="%s" target="_blank" title="Click to open page in new tab">%s</a>',val,val)
  } else {val}
}

# Search link-creating function
# Break into sentences and tag for search
sentenceSearch <- function(val) {
  # Parse into sentences
  parsed <- unlist(strsplit(val, "(?<=[[:punct:]])\\s(?=[A-Z])", perl=T))
  # Smoosh
  paste(parsed, collapse=" ")
}

caretFix <- function(val) {
  fixed <- gsub("<","&lt;",val)
  fixed <- gsub(">","&gt;",fixed)
  return(fixed)
}
# Set OpenAI API key
# Retrieves from system environment
# mykey <- Sys.getenv(c("OPENAI_API_KEY"))
# Sys.setenv(OPENAI_API_KEY = mykey )

# Load the CT_Pub data and CT_Repo data
CT_Pub_updated.df<- readRDS("CT_Pub_updated.df.Rds")

# Extract default three shot from CT_Pub
CT_Pub_updated_Step_1.df <- CT_Pub_updated.df[!CT_Pub_updated.df$NCTId %in% c("NCT00000620", "NCT01483560", "NCT04280783"), ]

##################
# Create CTSuggest UI
##################
ui <- fluidPage(
  useShinyjs(),
  
  # Use CSS to set the nav-bar and nav-pills
  tags$style(HTML("
    .navbar-nav {
  margin: 0 !important; 
  float: left !important; 
}
.navbar-header {
  text-align: left !important; 
  width: auto !important;
}
 
                  
    .nav-pills > li > a,
    .nav-pills .nav-link {
      background-color: #ffffff !important;
      color: #000000 !important;
    }
    
    .nav-pills > li > a.active,
    .nav-pills .nav-link.active {
      background-color: #ffffff !important;
      color: #000000 !important;
      border-bottom: 2px solid #D6001C !important;
    }
    .nav-pills .nav-link:hover {
        background-color: rgba(214, 0, 28, 0.5);
        color: white;
      }")),
  
  # A little JS to implement the enter key
  tags$script(src = "enter_button.js"),
  
  # 1) Single row that holds the left, center title, and right image
  fluidRow(
    
    
    
    # Middle column: the title, centered
    column(
      width = 8,
      div(
        style = "text-align:center;",
        h2("CT Suggest:  Clinical Trial Suggestion of Baseline Features",
           style = "color:#054664; font-weight: bold;")
      )
    )
    
    
    
  ),
  
  # Tab text
  title = "CT Suggest:  Clinical Trial Suggestion of Baseline Features",
  
  # Custom CSS for welcome message and Update button
  tags$head(
    tags$style(HTML("
      /* Custom CSS class for the welcome message */
      .fancy-welcome {
        color: #000000;                   /* Teal color */
        font-size: 24px;                  /* Increased font size */
        font-weight: bold;                /* Bold text */
        text-align: center;               /* Centered text */
        font-family: 'Georgia', serif;    /* Elegant and fancy font */
        background-color: white;          /* White background */
        padding: 20px;                     /* Padding for spacing */
        border-radius: 8px;                /* Rounded corners */
        box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1); /* Subtle shadow for depth */
        margin-bottom: 10px;               /* Space below the message */
      }
      
      /* Custom CSS class for the instructional paragraph */
      .instructional-text {
        color: #466B8E;                   /* Even darker blue color */
        font-size: 28px;                  /* Increased font size */
        font-weight: bold;                /* Bold text */
        text-align: center;               /* Centered text */
        font-family: 'Arial', sans-serif; /* Clean and professional font */
        background-color: #e6f7ff;        /* Light blue background */
        padding: 20px;                     /* Padding for spacing */
        border-radius: 8px;                /* Rounded corners */
        box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1); /* Subtle shadow for depth */
        margin-bottom: 20px;               /* Space below the paragraph */
      }
      
    /* --- Default (Inactive) Tabs: Grey Background with Black Text (Bold) --- */
.navbar-default .navbar-nav > li > a {
  background-color: #CCCCCC !important; /* Grey background */
  color: #000000 !important;           /* Black text */
  font-weight: bold !important;        /* Bold text */
  border-radius: 8px !important;       /* Rounded edges */
  margin-right: 2px !important;        /* Small gap between tabs */
  font-size: 18px !important;
  transition: background-color 0.3s ease-in-out, color 0.3s ease-in-out; /* Smooth transition */
}
/* --- Ensure Active Tab is Blue with White Text (Bold) --- */
.navbar-default .navbar-nav > li.active > a,
.navbar-default .navbar-nav > li > a.active {
  background-color: #0775A6 !important; /* Blue when active */
  color: #ffffff !important;           /* White text */
  font-weight: bold !important;        /* Keep text bold */
  border-radius: 8px !important;
}
/* --- Hover Effect for Inactive Tabs (Slightly Darker Grey) --- */
.navbar-default .navbar-nav > li:not(.active) > a:hover {
  background-color: #B3B3B3 !important; /* Slightly darker grey */
  color: #000000 !important;            /* Keep text black */
  font-weight: bold !important;
}
/* --- Hover Effect for Active Tab (Darker Blue) --- */
.navbar-default .navbar-nav > li.active > a:hover,
.navbar-default .navbar-nav > li > a:focus:hover {
  background-color: #055A87 !important; /* Slightly darker blue */
  color: #ffffff !important;
  font-weight: bold !important;
}
/* Default (Inactive) Tabs: Grey Background with Black Text */
.nav-tabs > li > a {
  background-color: #FAFAFA !important; /* Grey background */
  color: #000000 !important;           /* Black text */
  border-radius: 8px !important;       /* Rounded edges */
  font-size: 18px !important;          /* Bigger text */
  font-weight: bold !important;        /* Bold text */
  padding: 12px 24px !important;       /* Better spacing */
  margin-right: 5px !important;        /* Small space between tabs */
  transition: background-color 0.3s ease-in-out, color 0.3s ease-in-out; /* Smooth transition */
}
/* --- Ensure Active Tab is Blue with White Text (Bold) --- */
.nav-tabs > li.active > a,
.nav-tabs > li > a.active {
  background-color: #0775A6 !important; /* Blue when active */
  color: #ffffff !important;           /* White text */
  font-weight: bold !important;        /* Keep text bold */
  border-radius: 8px !important;
}
/* Hover Effect for Inactive Tabs */
.nav-tabs > li:not(.active) > a:hover {
  background-color: #B3B3B3 !important; /* Slightly darker grey */
  color: #000000 !important;            /* Keep text black */
  border-radius: 8px !important;        /* Maintain rounded corners */
}
/* Ensure Tab Content Has Rounded Corners */
.tab-content {
  border-radius: 8px !important;
  padding: 20px;
  background-color: #F5F5F5 !important; /* Light grey background */
}
      
      /* Optional: Additional styling for the Update button */
.btn-button {
  font-size: 18px; 
  padding: 12px 24px; 
}
.btn-button:hover {
  background-color: #008080; 
  transform: scale(1.05);   
}
/* --- NEW override for .btn-primary.btn-lg to be deep blue --- */
.btn-primary.btn-lg {
  background-color: #0775A6 !important; /* Deep Blue */
  color: #ffffff !important;           /* White text */
  border-color: #0775A6 !important;    
}
/* --- New class .btn-lightgray for large light-grey buttons with bigger text --- */
.btn-lightgray.btn-lg {
  background-color: #f0f0f0 !important; /* Light grey background */
  color: #000000 !important;           /* Black text */
  border-color: #cccccc !important;    /* Subtle grey border */
  font-weight: 500;                    /* Semi-bold if desired */
  font-size: 18px !important;          /* Slightly bigger text */
  padding: 12px 24px !important;       /* Increase padding to suit bigger text */
}
    "))
  ),
  
  tags$style(HTML("
        .custom-textarea .shiny-input-container {
            background-color: #CCCCCC;  /* Light grey background */
            border-radius: 5px;
            padding: 10px;
        }
        .custom-textarea textarea {
            font-weight: 600; /* Semi-bold text */
        }
    ")),
  
  # Allows scrolling of the sidebar panel and the main panel separately
  tags$head(
    tags$style(HTML("
    /* Keep or remove margin-right as you wish */
    .nav-link {
      margin-right: 50px; 
    }
    /* Force nav-pills to be horizontal even if .nav-stacked is used */
    .nav-pills.nav-stacked {
      display: flex !important;
      flex-direction: row !important;
    }
    .nav-pills.nav-stacked > li {
      float: none !important;
    }
    .siderbar { /* remove or comment out the next lines */
  /* max-height:70vh; */
  /* overflow-y: auto; */
}
.mainpanel {
  /* max-height:70vh; */
  /* overflow-y: auto; */
  /* overflow-x: hidden; */
}
    .content_wrapper { display:flex; }
  "))
  ),
  
  # Here start to separate the app into 3 main pages
  page_navbar(
    
    nav_panel("Overview",
              fluidRow(
                column(12,
                       div(style = "background-color: #CDE3ED; padding: 20px; border-radius: 8px;",
                           tags$h2("About CTSuggest", style = "font-weight: bold; color: #333333; font-size: 24px;"),
                           tags$p("CTSuggest, short for Clinical Trial Suggestion of Baseline Features using LLM, is a user-friendly tool based on the CTBench benchmark that helps researchers and clinicians design clinical trials by using Large Language Models (LLMs) to suggest baseline features to be collected based on existing trial metadata. Baseline features are the critical characteristics of the trial participants that researchers and clinicians need to monitor before and after treatment in a clinical trial. In CTSuggest, you can choose an existing clinical trial from the database used in CTBench, or create a custom trial tailored to your needs. Once you select or create a trial, CTSuggest uses LLMs to generate key baseline features.",
                                  style = "font-weight: 600; color: #333333; font-size: 16px;"),
                           tags$p("Additionally, if baseline features are generated for an existing trial, CTSuggest can check how well these generated features match up with the baseline features actually measured in that trial by using LLMs. This step allows users to verify that the features suggested by CTSuggest are appropriate, helping to improve confidence in the app as well as the quality of the outcomes for trials which use CTSuggest. CTSuggest is an experiment with future potential designed by students to simplify complex tasks, and advance medical research and treatment effectiveness in the future.",
                                  style = "font-weight: 600; color: #333333; font-size: 16px;"),
                           tags$h2("Important instructions", style = "font-weight: bold; color: #333333; font-size: 24px;"),
                           tags$p("1. In step 1, you can either load an existing trial or create a blank custom trial by hitting the respective buttons. If you customize a trial (either by creating a blank one or modifying an existing one), clicking 'Update' saves the information for future steps. You also have the option to download the saved information as a JSON file ", 
                                  style = "font-weight: 600; color: #333333; font-size: 16px;"),
                           tags$p("2. In step 2, when you click on 'Generate' in the Report tab, the saved information from Step 1 is passed into an LLM which generates the suggested baseline features along with explanations for why each feature was suggested and how it relates to the trial objectives. By default, the LLM used here is gpt-4o. You can download the generated report as a JSON file. In the Options tab, you can select different LLMs to suggest baseline features, choose your in context learning (ICL) settings (zero shot learning vs. three shot learning), and choose whether or not explanations should be generated. If you choose the three shot learning ICL, you have the option to choose the three prior examples the LLM will study for generating the descriptors. You can also see the generation and explanation prompts that the LLM uses.", 
                                  style = "font-weight: 600; color: #333333; font-size: 16px;"),
                           tags$p("3. In step 3, if you generated features for an existing trial, you can hit the 'Run Evaluation' button to call an LLM to match the generated (candidate) baseline features to the actual (reference) baseline features measured in the trial. A report is then generated that contains a list of matches, unmatched candidate features, unmatched reference features, and performance metric. You also have the option to download the report as a JSON file.", 
                                  style = "font-weight: 600; color: #333333; font-size: 16px;"),
                           tags$h2("Feedback", style = "font-weight: bold; color: #333333; font-size: 24px;"),
                           
                           tags$h2("References", style = "font-weight: bold; color: #333333; font-size: 24px;"),
                           tags$p(
                             tags$a("1. [Redacted for anonymity]", 
                                    
                                    style = "font-weight: 600; color: #333333; font-size: 16px;", 
                                    target = "_blank")
                           ),
                           
                           tags$p(
                             tags$a("2. [Redacted for anonymity]
                             ",
                                    
                                    style = "font-weight: 600; color: #333333; font-size: 16px;", 
                                    target = "_blank")),
                             tags$p(
                               tags$a("3. [Redacted for anonymity] ", 
                                       
                                      style = "font-weight: 600; color: #333333; font-size: 16px;", 
                                      target = "_blank"))
                       )
                )
              ),
              tags$hr(style = "margin-bottom: 0.3px;"),
              tags$p("CTSuggest is by developed with the objective of implementing Artificial Intelligence in the healthcare domain.",
                     tags$br(),
                     
                     tags$br(),
                     tags$i(paste0("CTSuggest version: ",version))
              )),
    
    nav_panel("Step 1: Specify Trial",
              
              # First row: Blue background now starts below "Specify Trial"
              fluidRow(
                column(12,
                       div(
                         style = "background-color: #CDE3ED; padding: 20px; border-radius: 8px;",
                         tags$p(
                           "Enter trial information in boxes below.
                         Start from an existing trial by selecting NCT ID and hit 'Load Existing Trial',
                         or create a trial from scratch by selecting 'Create Blank Trial'.",
                           style = "color: #A1A1A; font-weight: 600;"),
                         # style = "color: #A1A1A; font-weight: 600; font-size: 20px;"),  # Semi-bold text
                         div(style = "display: flex; align-items: center; gap: 25px;",
                             # Bold label via HTML
                             selectizeInput(
                               inputId = "NCTid",
                               label = HTML("<strong>Choose an NCT ID:</strong>"),  # Bold label
                               choices = CT_Pub_updated_Step_1.df$NCTId,
                               selected = NULL,  # Ensures no ID is selected by default
                               width = "300px"
                             ),            
                             actionButton("load_data", "Load Existing Trial", class = "btn btn-primary btn-lg btn-button",),
                             tags$span(" OR ", style = "margin: 0 10px; font-weight: bold;"),
                             # "Custom" button
                             actionButton("custom_data", "Create Blank Trial", class = "btn btn-primary btn-lg btn-button",
                                          style = "margin-left:10px;")
                         ),
                         
                         uiOutput("error_message"),
                         tags$p(
                           "If you have loaded an existing trial and wish to generate and evaluate features for that trial, continue to Step 2.
                           If you are modifying an existing trial or creating a blank trial, edit the fields below and hit 'Update', then go to Step 2.
                           Note: if you modify an existing trial or create a blank trial, you will not be able to perform Step 3.",
                           style = "color: #333333; font-weight: 600;"  # Semi-bold text
                         )
                       )
                       
                ),
                
                
                # Second row: everything that was in the old mainPanel
                fluidRow(
                  column(12,
                         class = "mainpanel",
                         
                         # Heading moved slightly down and left-aligned
                         tags$p(
                           "Clinical Trial Information",
                           style = "color: #A1A1A; font-size: 24px; font-weight: bold; margin-top: 10px; margin-bottom: 10px; text-align: left;"  
                         ),  # Slightly larger bottom margin
                         
                         # Add spacing before the input section
                         div(# style = "margin-top: 20px;",  # This moves everything below a bit down
                           
                           # Title input box (comes immediately after the heading)
                           textAreaInput("Title",
                                         label = HTML("<strong>Title</strong><span style='color: red;'>*</span>"), 
                                         value = "",
                                         rows = 1,
                                         width="100%"),
                           
                           textAreaInput("BriefSummary", 
                                         label = HTML("<strong>Brief Summary</strong><span style='color: red;'>*</span>"), 
                                         value = "",
                                         rows = 2,
                                         width="100%"),
                           
                           textAreaInput("Condition", 
                                         label = HTML("<strong>Condition</strong><span style='color: red;'>*</span>"), 
                                         value = "",
                                         rows = 1,
                                         width="100%"),
                           
                           tagList(
                             strong("Eligibility Criteria"),
                             textAreaInput("InclusionCriteria", 
                                           label = HTML("<span style='font-size:13px;'><strong>Inclusion Criteria</strong><span style='color:red;'>*</span></span>"), 
                                           value = "",
                                           rows = 3,
                                           width = "100%"),
                             
                             textAreaInput("ExclusionCriteria", 
                                           label = HTML("<span style='font-size:13px;'><strong>Exclusion Criteria</strong><span style='color:red;'>*</span></span>"), 
                                           value = "",
                                           rows = 3,
                                           width = "100%")),
                           
                           textAreaInput("Intervention", 
                                         label = HTML("<strong>Intervention</strong><span style='color: red;'>*</span>"), 
                                         value = "",
                                         rows = 1,
                                         width="100%"),
                           
                           textAreaInput("Outcome", 
                                         label = HTML("<strong>Outcome</strong><span style='color: red;'>*</span>"), 
                                         value = "",
                                         rows = 1,
                                         width="100%"),
                           
                           div(id = "Ref_nct_id",
                               tags$p(tags$p(HTML("<strong>Reference NCT ID:</strong> "),
                                             textOutput("ref_nct_id",
                                                        inline = TRUE)))),
                           textAreaInput("ActualFeatures", 
                             label = HTML("<strong>Actual Features (not required, used only for Step 3 evaluation of existing trials)</strong>"), 
                             value = "",
                             rows = 2,
                             width = "100%")
                           
                         ),  # End of div
                         
                         fluidRow(
                           column(12,  # Using a full-width column to contain both buttons
                                  div(
                                    style = "display: flex; justify-content: space-between; align-items: center;",
                                    # Left-aligned Update button
                                    actionButton("update_custom", "Update", class = "btn btn-primary btn-lg btn-button", 
                                                 style = "margin-right: 20px;"),
                                    # Right-aligned Download button
                                    downloadButton("downloadData_trial",
                                                   "Download clinical trial information as JSON file",
                                                   class = "btn-lightgray")
                                  )
                           )
                         ),
                         
                  )
                )
              )
    ),
    
    
    
    nav_panel("Step 2: Generate Descriptors",
              
              # Tabset Panel (Report & Options)
              tabsetPanel(
                id = "step2tabs",
                tabPanel("Report",
                         fluidRow(
                           column(12,
                                  class = "mainpanel",
                                  # Keep Blue Box for explanations
                                  div(style = "background-color: #CDE3ED; padding: 20px; border-radius: 8px;",
                                      
                                      tags$p(
                                        "Click the 'Generate' button to suggest baseline features for the trial using the large language model.
                                         Use 'Options' tab to specify options used.
                                         For quicker execution, turn off 'Explanation' in 'Options'.
                                         Go to Step 3 for Evaluation.",
                                        style = "color: #333333; font-weight: 600;" # font-size: 18px; margin-bottom: 15px;"  # Semi-bold
                                      ),
                                      # Generate
                                      div(style = "text-align: left; margin-bottom: 20px;",
                                          actionButton("generate", "Generate", class = "btn btn-primary btn-lg btn-button")
                                      )
                                  ),
                                  tags$h4(HTML("<strong>Suggested Baseline Features:</strong>"), style = "margin-top: 20px;"),  ## Adjust vertical spacing
                                  uiOutput("generateError"),
                                  uiOutput("error_message_three_Report"),
                                  # Place Output Below Generate Button
                                  htmlOutput("resultTextOutput"),
                                  # Download Button - Right aligned
                                  div(style = "text-align: right;",
                                      downloadButton("downloadData_generate",
                                                     "Download suggested baseline feature report as JSON file",
                                                     class = "btn-lightgray")
                                  )
                           )
                         )
                ),
                
                tabPanel("Options", 
                         fluidRow(
                           column(12,
                                  class = "mainpanel",
                                  
                                  # FIRST GREY BACKGROUND SECTION (Everything Inside is Bold)
                                  div(style = "background-color: #CDE3ED; padding: 20px; border-radius: 8px;",
                                      tags$p(style = "font-weight: 600;", 
                                             "Specify options used to generate suggested baseline features."),
                                      # Model Selection (Bold Label)
                                      selectInput("model", 
                                                  label = HTML("<strong>LLM model used to generate baseline features</strong>"),
                                                  # choices = c("gpt-4o"),
                                                  choices = c("gpt-4o", "Meta-Llama-3.1-8B-Instruct"),
                                                  selected = "gpt-4o",
                                                  multiple = FALSE),
                                      tags$p(style = "font-weight: 600;", 
                                             "Three-shot improves performance by monitoring three trial examples. The alternative zero-shot method provides good results faster. If using the three-shot method, the default three trials are recommended, but you may change which three trials are used. Note: Each of the three trials selected for the three-shot method must be distinct from one another and the existing trial loaded, if applicable."),
                                      # Three-Shot Checkbox (Semi-Bold Label)
                                      checkboxInput("ThreeShotCheck",
                                                    label = HTML("<span style='font-weight: 600;'>Use Three-shot (else Zero-shot)</span>"),
                                                    value = TRUE,
                                                    width = "100%"), 
                                      # Example NCT ID Selections (Bold Labels)
                                      fluidRow(
                                        column(3, 
                                               selectizeInput("NCTid_eg1", HTML("<strong>Choose an NCT ID for trial example 1:</strong>"), 
                                                              choices = CT_Pub_updated.df$NCTId,
                                                              selected = "NCT00000620",
                                                              options = list(create = FALSE, placeholder = "Search or select an NCT ID"))
                                        ),
                                        column(3, 
                                               selectizeInput("NCTid_eg2", HTML("<strong>Choose an NCT ID for trial example 2:</strong>"), 
                                                              choices = CT_Pub_updated.df$NCTId,
                                                              selected = "NCT01483560",
                                                              options = list(create = FALSE, placeholder = "Search or select an NCT ID"))
                                        ),
                                        column(3, 
                                               selectizeInput("NCTid_eg3", HTML("<strong>Choose an NCT ID for trial example 3:</strong>"), 
                                                              choices = CT_Pub_updated.df$NCTId,
                                                              selected = "NCT04280783",
                                                              options = list(create = FALSE, placeholder = "Search or select an NCT ID"))
                                        ),
                                        # Error Message for Three-Shot
                                        uiOutput("error_message_three_Options"),
                                      ),
                                      
                                      tags$p(uiOutput("explanation_info")),
                                      checkboxInput("explain",
                                                    label = HTML("<span style='font-weight: 600;'>Generate Explanation</span>"),
                                                    value=TRUE,
                                                    width="100%"
                                      ),
                                      
                                      # Description for Explanation
                                      tags$p(style = "font-weight: 600;", 
                                             "Click 'Update' to generate report then return to Step 2 Report to see generate report."),
                                      
                                      # Update Button moved up and aligned to the left
                                      div(style = "text-align: left;",
                                          actionButton("update", "Update", class = "btn btn-primary btn-lg btn-button")
                                      ),
                                      br(),
                                       div(style = "font-weight: 600;", 
                                              "Toggle the 'Use Three-shot' checkbox to view the corresponding system prompt templates. Similarly, use the 'Generate Explanation' checkbox to show or hide the explanation prompt template.
To view the full, actual prompts sent to the model, first generate a report, then go to the 'Report' page and download JSON."
                                       ),
                                  ),
                                  
                                  
                                  # SECOND GREY BACKGROUND SECTION
                                  div(style = "background-color: #f5f5f5; padding: 20px; border-radius: 8px;",
                                      
                                      # System Prompt Templates: show one based on the three-shot option
                                      conditionalPanel(
                                        condition = "input.ThreeShotCheck == true",
                                        div(class = "custom-textarea",
                                            textAreaInput("systemPrompt_Three_shot",
                                                          label = HTML("<strong>System Prompt Template (Three-shot)</strong>"),
                                                          value = systemPromptText_Three_shot.default,
                                                          rows = 8,
                                                          width = "100%")
                                        )
                                      ),
                                      conditionalPanel(
                                        condition = "input.ThreeShotCheck == false",
                                        div(class = "custom-textarea",
                                            textAreaInput("systemPrompt",
                                                          label = HTML("<strong>System Prompt Template</strong>"),
                                                          value = systemPromptText.default,
                                                          rows = 8,
                                                          width = "100%")
                                        )
                                      ),
                                      conditionalPanel(
                                        condition = "input.explain == true",
                                        div(class = "custom-textarea",
                                            textAreaInput("explanationPrompt",
                                                          label = HTML("<strong>Explanation Prompt Template</strong>"),
                                                          value = "Provide detailed explanations for each selected baseline feature, linking them directly to the study’s objectives or hypotheses. For instance, explain how age and gender are related to the condition under study, supported by data or literature indicating their relevance. Also, note any statistical models or analyses that demonstrate the impact of these demographics on the study's outcomes.",
                                                          rows = 4,
                                                          width = "100%")
                                        )
                                      ),
                                      tags$script(HTML("$(document).on('shiny:connected', function() {
                                                        $('#systemPrompt').prop('disabled', true);
                                                        $('#systemPrompt_Three_shot').prop('disabled', true);
                                                        $('#explanationPrompt').prop('disabled', true);});"))
                                  )
                           )
                         )
                )
              )
    ),
    
    
    nav_panel("Step 3: Evaluate",
              fluidRow(
                column(
                  12, 
                  class = "mainpanel",
                  div(
                    style = "background-color: #CDE3ED; padding: 20px; border-radius: 8px;",
                    
                    # Instructional text
                    tags$p(
                      "Evaluation utilizes an LLM-as-a-judge to compare the generated candidate baseline features to the reference baseline features for the reference NCT ID trial.
                      Click 'Run Evaluation' to perform the evaluation using gpt‑4o. 
                      The candidate features in box will be evaluated. The candidate features can be edited if desired.",
                      style = "color: #A1A1A; font-weight: 600; text-align: left;"
                    ),
                    tags$p(
                      "Note: Evaluation only works for existing NCT ID that have not been modified.",
                      style = "color: #A1A1A; font-weight: 600; text-align: left;"
                    ),
                    # Candidate Features text area
                    textAreaInput(
                      "CandidateFeatures", 
                      label = HTML("<strong>Candidate Features:</strong>"),
                      value = "",
                      rows = 2,
                      width = "100%"
                    ),
                    
                    # Run Evaluation Button (now appears below the Candidate Features box)
                    actionButton("evaluation", "Run Evaluation", 
                                 class = "btn btn-primary btn-lg btn-button", 
                                 style = "margin-top: 10px;")
                  ),
                  tags$h4(HTML("<strong>Evaluation Report:</strong>"), style = "margin-top: 20px;"),
                  htmlOutput("evalResultTextOutput"),
                  div(style = "text-align: right;",
                      downloadButton(
                        "downloadData_evaluate",
                        "Download evaluation report as JSON file",
                        class = "btn-lightgray")
                  )
                )
              )
    ),
    
    
    
    id = "page"
  ))

# Define server logic 
server <- function(input, output, session) {
  shinyjs::hide("resultTextOutput")
  disableRDF <- reactiveVal(TRUE) 
  trialState <- reactiveVal("No Trial")
  loadedNCTid <- reactiveVal("")
  output$explanation_info <- renderUI({
    HTML(paste0(
      "<div style='color: #333333; font-weight: 600;'>",
      "Explanations will be generated by ", input$model, ". No explanations runs faster.",
      "</div>"
    ))
  })
  evalSystemPrompt <- reactiveVal("")
  evalUserPrompt <- reactiveVal("")
  isEmpty <- function(x) {
    if (is.null(x)) return(TRUE)
    return(nchar(trimws(x)) == 0)
  }
  output$ref_nct_id <- renderText({
    loadedNCTid()
  })
  output$selected_model <- renderText({
    input$model
  })
  # We store the final, currently relevant trial data here
  trialData <- reactiveValues(
    Title = NULL,
    BriefSummary = NULL,
    Condition = NULL,
    EligibilityCriteria = NULL,
    Intervention = NULL,
    Outcome = NULL,
    ActualFeatures = NULL
  )
  
  # We'll use either the `gpt-4-0613` or `gpt-4-turbo-preview` OpenAI models (22 Feb 2024)
  trialOrigin <- reactiveVal("")
  modelText <- reactiveVal(c("Meta-Llama-3.1-8B-Instruct")) # Forced initial value
  modelText_evaluate <- reactiveVal(c("Meta-Llama-3.1-8B-Instruct")) # Forced initial value
  resultText <- reactiveVal("") # Forced initial value
  
  #Reactive Values for Evaluation
  evalResultText <- reactiveVal("")
  finalEvalData <- reactiveVal()
  
  tripleTable <- reactiveVal("")     # For display
  downloadJson <- reactiveVal("")   # For download
  
  entityDescription <- reactiveVal("Click a row to see a description of that entity")
  description.df <- reactiveVal("")
  
  promptText <- reactiveVal("")
  systemPrompt <- reactiveVal("")
  
  whichCol <- reactiveVal("subject")  # Changes depending on which cell user selects
  
  # Using purrr's insistently() to retry
  rate <- rate_delay(5) # retry rate 
  
  risky_create_completion <- function(prompt, model) {
    
    if (startsWith(model, "gpt-")) {
      client <- OpenAI()
    } else if (startsWith(model, "o1-")) {
      client <- OpenAI()
    } else {
      client <- OpenAI(
        base_url = "http://localhost:5000/v1/"
      )
    }
    client$chat$completions$create(
      model = model,
      messages = list(
        list(
          "role" = "system",
          "content" = systemPrompt()
        ),
        list(
          "role" = "user",
          "content" = prompt
        )
      )
    )
  }
  insistent_create_completion <- insistently(risky_create_completion, rate, quiet = FALSE)
  
  observeEvent(input$update, {
    if (trialOrigin() == "Loaded") {
      trialState("Modified")
    }
    shinyjs::show("resultTextOutput")
  })
  
  # Remove input UI components if required
  observeEvent(input$disableRDF, {
    disableRDF(input$disableRDF)
  })
  
  # Manage NCT ID selection, potentially resetting states
  observeEvent(input$select_nct, {
    if (trialOrigin() != "Custom") {  # Only update if not in custom mode
      updateTextInput(session, "NCTid", value = input$select_nct)
      trialState("Loaded")
    }
  })
  
  # Output the current trial state somewhere in the UI
  output$currentTrialStateStep1 <- renderText({
    switch(trialState(),
           "No Trial" = "Trial State - No trial loaded or created yet.",
           "Loaded" = "Trial State - A trial has been loaded.",
           "Custom" = "Trial State - A custom trial has been created.",
           "Custom Modified" = "Trial State - Trial information has been updated.",
           "Modified" = "Trial State - Trial details have been modified."
    )
  })
  
  output$currentTrialStateStep2 <- renderText({
    switch(trialState(),
           "No Trial" = "Trial State - No trial loaded or created yet.",
           "Loaded" = "Trial State - A trial has been loaded.",
           "Custom" = "Trial State - A custom trial has been created.",
           "Custom Modified" = "Trial State - Trial information has been updated.",
           "Modified" = "Trial State - Trial details have been modified."
    )
  })
  
  output$currentTrialStateStep3 <- renderText({
    switch(trialState(),
           "No Trial" = "Trial State - No trial loaded or created yet.",
           "Loaded" = "Trial State - A trial has been loaded.",
           "Custom" = "Trial State - A custom trial has been created.",
           "Custom Modified" = "Trial State - Trial information has been updated.",
           "Modified" = "Trial State - Trial details have been modified."
    )
  })
  
  trialModified <- reactiveVal(FALSE)
  customMode <- reactiveVal(FALSE)
  # The load data button
  observeEvent(input$load_data, {
    
    show("ActualFeatures")
    shinyjs::disable("ActualFeatures")
    output$generateError <- renderUI({ NULL })
    output$error_message_three_Report <- renderUI({ span("") })
    output$error_message_three_Options <- renderUI({ span("") })
    
    # enter the id
    id <- input$NCTid
    loadedNCTid(id)
    shinyjs::show("Ref_nct_id")
    selected_row <- CT_Pub_updated.df[CT_Pub_updated.df$NCTId == id, ]
    
    # Make sure it is the correct id
    if (nrow(selected_row) == 0){
      output$error_message <- renderUI({span("Cannot find this NCTId.", style = "color: red;")})
      output$result_text <- renderText({ "" })
      trialState("No Trial")
      trialOrigin("")  # Clear any previous origin since no trial is loaded
      return()
    } else {
      # If it is correct, get the information from dataset
      output$error_message <- renderUI({span("")})
      Title <- selected_row$BriefTitle
      BriefSummary <- selected_row$BriefSummary
      Condition <- selected_row$Conditions
      EligibilityCriteria <- selected_row$EligibilityCriteria
      Intervention <- selected_row$Interventions
      Outcome <- selected_row$PrimaryOutcomes
      
      # Assign Inclusion and Exclusion Criteria
      split_text <- str_split(EligibilityCriteria, "Exclusion Criteria:", simplify = TRUE)
      InclusionCriteria <- str_trim(split_text[1])
      InclusionCriteria <- sub("^Inclusion Criteria:\\s*", "", InclusionCriteria)
      ExclusionCriteria <- str_trim(split_text[2])
      
      # Get the system prompt from input
      systemPrompt(isolate(paste(input$systemPrompt)))
      prompt <- paste0("##Question: \n\n<Title>", Title,
                       "\n<Brief Summary>", BriefSummary,
                       "\n<Condition>", Condition,
                       "\n<Eligibility Criteria>", EligibilityCriteria,
                       "\n<Intervention>", Intervention,
                       "\n<Outcome>", Outcome,
                       "\n\n##Answer:")
      
      # Update the input boxes in UI part with the data
      updateTextAreaInput(session, "Title", value = Title)
      updateTextAreaInput(session, "BriefSummary", value = BriefSummary)
      updateTextAreaInput(session, "Condition", value = Condition)
      updateTextAreaInput(session, "Intervention", value = Intervention)
      updateTextAreaInput(session, "Outcome", value = Outcome)
      updateTextAreaInput(session, "InclusionCriteria", value = InclusionCriteria)
      updateTextAreaInput(session, "ExclusionCriteria", value = ExclusionCriteria)
      updateTextAreaInput(session, "ActualFeatures", value = selected_row$Paper_BaselineMeasures_Corrected)
      
      # Set trial data
      trialData$Title               <- Title
      trialData$BriefSummary        <- BriefSummary
      trialData$Condition           <- Condition
      trialData$EligibilityCriteria <- EligibilityCriteria
      trialData$Intervention        <- Intervention
      trialData$Outcome             <- Outcome
      trialData$ActualFeatures      <- selected_row$Paper_BaselineMeasures_Corrected
      trialData$InclusionCriteria   <- InclusionCriteria
      trialData$ExclusionCriteria   <- ExclusionCriteria
      
      
      resultText("")  # Clears the resultText for Generate Descriptors
      evalResultText("")  # Clears the evaluation results text
      finalEvalData(NULL)  # Resets the evaluation data
      updateTextAreaInput(session, "CandidateFeatures", value = "")
      output$evalResultTextOutput <- renderUI({ NULL })
      # Set trial state and origin
      trialState("Loaded")
      trialOrigin("Loaded")
      trialModified(FALSE)   # Indicate that this trial was loaded from data
    }
  })
  
  
  
  
  # The custom_data button logic
  observeEvent(input$custom_data, {
    customMode(TRUE)
    # Hide the ActualFeatures field so user doesn't see it at all in custom mode
    hide("Ref_nct_id")
    hide("ActualFeatures")
    # This will clear each text area so the user can manually fill them in.
    updateTextAreaInput(session, "Title",                 value = "")
    updateTextAreaInput(session, "BriefSummary",          value = "")
    updateTextAreaInput(session, "Condition",             value = "")
    updateTextAreaInput(session, "EligibilityCriteria",   value = "")
    updateTextAreaInput(session, "InclusionCriteria",     value = "")
    updateTextAreaInput(session, "ExclusionCriteria",     value = "")
    updateTextAreaInput(session, "Intervention",          value = "")
    updateTextAreaInput(session, "Outcome",               value = "")
    updateTextAreaInput(session, "ActualFeatures",        value = "")
    
    # (Optional) also reset the trialData
    trialData$Title               <- ""
    trialData$BriefSummary        <- ""
    trialData$Condition           <- ""
    trialData$EligibilityCriteria <- ""
    trialData$Intervention        <- ""
    trialData$Outcome             <- ""
    trialData$ActualFeatures      <- ""
    trialData$InclusionCriteria <- ""
    trialData$ExclusionCriteria <- ""
    trialState("Custom")
    trialOrigin("Custom")
    trialModified(FALSE)
    
    # Clear previous generated results when switching to custom mode
    resultText("")  # Clears the resultText for Generate Descriptors
    evalResultText("")  # Clears the evaluation results text
    finalEvalData(NULL)  # Resets the evaluation data
    updateTextAreaInput(session, "CandidateFeatures", value = "")  # Clear Candidate Features input
    output$evalResultTextOutput <- renderUI({ NULL })
  })
  
  # The new "Update" button logic
  observeEvent(input$update_custom, {
    output$generateError <- renderUI({ NULL })
    output$error_message_three_Report <- renderUI({ span("") })
    output$error_message_three_Options <- renderUI({ span("") })
    # Store the user-typed fields in trialData
    trialData$Title               <- input$Title
    trialData$BriefSummary        <- input$BriefSummary
    trialData$Condition           <- input$Condition
    trialData$InclusionCriteria   <- input$InclusionCriteria
    trialData$ExclusionCriteria   <- input$ExclusionCriteria
    trialData$EligibilityCriteria <- paste(
      "Inclusion Criteria:\n\n", input$InclusionCriteria, 
      "\n\nExclusion Criteria:\n\n", input$ExclusionCriteria, 
      sep = "")
    trialData$Intervention        <- input$Intervention
    trialData$Outcome             <- input$Outcome
    # # Up to you if you want to store ActualFeatures from user
    # trialData$ActualFeatures      <- input$ActualFeatures
    
    # Reset outputs for Step 2 and Step 3
    resultText("")  # Clears the resultText for Generate Descriptors
    evalResultText("")  # Clears the evaluation results text
    finalEvalData(NULL)  # Resets the evaluation data
    updateTextAreaInput(session, "CandidateFeatures", value = "")  # Clear Candidate Features input
    output$evalResultTextOutput <- renderUI({ NULL })
    # Update state based on the origin
    trialState("Custom Modified")
    trialOrigin("Custom")
    trialModified(TRUE)
    customMode(TRUE)
    showModal(modalDialog(
      title = "Trial Information Updated",
      "Continue to edit or go to step 2 to suggest baseline features for those trial.",
      easyClose = TRUE,
      footer = modalButton("Close")
    ))
  })
  
  observeEvent(input$page, {
    # Whenever user navigates to Step 2 at the top level...
    if (input$page == "Step 2: Generate Descriptors") {
      # ...force the sub-tab to "Report"
      updateTabsetPanel(session, "step2tabs", selected = "Report")
    }
  })
  
  observeEvent(input$generate, {
    if (trialState() == "No Trial" ||
        is.null(input$NCTid) ||
        isEmpty(input$Title) ||
        isEmpty(input$BriefSummary) ||
        isEmpty(input$Condition) ||
        (isEmpty(input$InclusionCriteria) && isEmpty(input$ExclusionCriteria)) ||
        isEmpty(input$Intervention) ||
        isEmpty(input$Outcome)) {
      
      output$generateError <- renderUI({
        tags$p("No trial has been specified. Return to Step 1.", style = "color: red; font-weight: bold;")
      })
      return()  # Stop further processing
    } else {
      # Clear any previous error message
      output$generateError <- renderUI({ NULL })
      shinyjs::show("resultTextOutput")
      
      # Use the values saved in trialData.
      localTitle               <- trialData$Title
      localBriefSummary        <- trialData$BriefSummary
      localCondition           <- trialData$Condition
      localEligibilityCriteria <- trialData$EligibilityCriteria
      localIntervention        <- trialData$Intervention
      localOutcome             <- trialData$Outcome
      
      # Build the prompt from the saved trialData.
      prompt <- paste0("##Question:\n\n<Title>", localTitle,
                       "\n<Brief Summary>", localBriefSummary,
                       "\n<Condition>", localCondition,
                       "\n<Eligibility Criteria>", localEligibilityCriteria,
                       "\n<Intervention>", localIntervention,
                       "\n<Outcome>", localOutcome,
                       "\n\n##Answer:")
      
      # Model logic:
      modelText(isolate(input$model))
      explain <- isolate(input$explain)
      result <- list()
      
      resultText("")    # Clear previous results
      evalResultText("")
      finalEvalData(NULL)
      updateTextAreaInput(session, "CandidateFeatures", value = "")
      output$evalResultTextOutput <- renderUI({ NULL })
      
      if (explain == TRUE) {
        systemPrompt(isolate(paste(
          systemPrompt(),
          "Use bold text for headings and separate each section with a line break for the explanation, do not include any colon or hyphen. Example for explanation part:
         **Age**\nAge is a critical factor in type 2 diabetes studies, influencing metabolic control and treatment response. It impacts insulin sensitivity and beta-cell function, essential in evaluating the trial's aim to achieve glycemic control with minimal weight gain. Studies suggest metabolic characteristics and treatment responses vary significantly with age, affecting HbA1c outcomes.\n
         **Sex**\nSex differences affect diabetes pathophysiology and treatment efficacy. Males and females may respond differently to diabetic medications due to hormonal influences, body fat distribution, and lifestyle factors. These differences can significantly impact the trial’s endpoints of glycemic control and weight change.\n
         **BMI**\nAs the trial specifically targets achieving glycemic control with minimal weight gain, BMI is crucial for baselining and monitoring weight change. Obesity is a key component in type 2 diabetes, affecting insulin resistance and drug metabolism, impacting both therapy outcomes and risks.\n
         **HbA1c**\nThe trial’s primary outcome is defined through HbA1c levels, with eligibility specifying patients with levels between 7.5% and 10%. HbA1c at baseline enables comparison in achieving the target of ≤ 7.4%. It directly reflects glucose control over time, crucial for evaluating the interventions' effectiveness.\n
         **Duration of diabetes**\nThis metric can influence treatment responses and risk of complications due to the progressive nature of type 2 diabetes. Longer duration often correlates with more advanced beta-cell dysfunction, influencing the ability to achieve and maintain target HbA1c levels and manage weight.\n
         **Current oral antidiabetic therapy type and dose**\nUnderstanding the type and dose of current therapy provides insight into the baseline level of disease control and helps stratify patients by their potential responsiveness to the interventions (exenatide and insulin glargine). The stability of this treatment for at least three months prior serves to standardize participants' metabolic status at baseline."
        )))
      }
      
      promptText(prompt)
      
      result.short <- list()
      
      add_backticks <- function(s) {
        s <- as.character(s)
        parts <- unlist(strsplit(s, "[,\n\\s]+"))
        parts <- trimws(parts)
        parts <- parts[parts != ""]
        parts <- paste0("`", parts, "`")
        paste(parts, collapse = ", ")
      }
      
      candidate_features <- sub(".*\\{([^}]*)\\}.*", "\\1", resultText())
      candidate_features <- sub("\\n+$", "", candidate_features)
      candidate_features <- sub("^\\s+", "", candidate_features)
      
      updateTextAreaInput(session, "CandidateFeatures", value = candidate_features)
    }
  })
  
  
  build_eval_prompt <- function(reference, candidate, qstart, promptNum) {
    # Define the system message
    system <- systemPromptText_Evaluation.gpt
    if (promptNum == 2){
      system = systemPromptText_Evaluation.llama
    }
    # Start building the question message
    question <- paste("\nHere is the trial information: \n\n", qstart, "\n\n", sep = "")
    
    # Add the reference features
    question <- paste(question, "Here is the list of reference features: \n\n", sep = "")
    for (i in seq_along(reference)) {
      question <- paste(question, i, ". ", reference[[i]], "\n", sep = "")
    }
    
    
    # Add the candidate features
    question <- paste(question, "\nCandidate features: \n\n", sep = "")
    for (i in seq_along(candidate)) {
      question <- paste(question, i, ". ", candidate[[i]], "\n", sep = "")
    }
    
    return (c(system, question))
  }
  
  get_question_from_row <- function(row) {
    # Extract relevant fields from the row
    title <- row["BriefTitle"]
    brief_summary <- row["BriefSummary"]
    condition <- row["Conditions"]
    eligibility_criteria <- row["EligibilityCriteria"]
    intervention <- row["Interventions"]
    outcome <- row["PrimaryOutcomes"]
    
    # Build the question string by concatenating the extracted fields
    question <- ""
    question <- paste(question, "<Title> \n", title, "\n", sep = "")
    question <- paste(question, "<Brief Summary> \n", brief_summary, "\n", sep = "")
    question <- paste(question, "<Condition> \n", condition, "\n", sep = "")
    question <- paste(question, "<Eligibility Criteria> \n", eligibility_criteria, "\n", sep = "")
    question <- paste(question, "<Intervention> \n", intervention, "\n", sep = "")
    question <- paste(question, "<Outcome> \n", outcome, "\n", sep = "")
    
    return(question)
  }
  
  extract_elements <- function(s) {
    # Define the pattern to match text within backticks
    pattern <- "`(.*?)`"
    
    # Use the regmatches and gregexpr functions to find all matches
    elements <- regmatches(s, gregexpr(pattern, s, perl = TRUE))[[1]]
    
    # Remove the enclosing backticks from the matched elements
    elements <- gsub("`", "", elements)
    
    return(elements)
  }
  
  extract_json <- function(text) {
    # Regular expression to detect JSON objects or arrays, allowing nested structures
    json_pattern <- "\\{(?:[^{}]|(?R))*\\}|\\[(?:[^[\\]]|(?R))*\\]"
    
    # Extract all matches
    matches <- regmatches(text, gregexpr(json_pattern, text, perl = TRUE))[[1]]
    
    # Validate JSON strings by attempting to parse
    valid_json <- matches[sapply(matches, function(x) {
      tryCatch({
        fromJSON(x)
        TRUE
      }, error = function(e) FALSE)
    })]
    
    return(valid_json)
  }
  
  RemoveHallucinations_v2<-function(Matches,ReferenceList,CandidateList){
    # Matches should be a list containing the matches, with Matches[1] being from
    # the reference list and Matches[2] being from the candidate list
    # ReferenceList should be the true reference feature list
    # CandidateList should be the true candidate feature list
    # 
    # Currently, this extracts all true (non-hallucinated) matches, all addition
    # match hallucinations (just the hallucinated feature, not the whole match), 
    # and all multi-match hallucinations (again, just the hallucinated feature),
    # and calculates the corrected metrics.
    
    # count the number of times each feature appears in each list; useful for
    # multi-match hallucination identification
    Rtab<-as.data.frame(table(ReferenceList))
    Ctab<-as.data.frame(table(CandidateList))
    MRtab<-as.data.frame(table(Matches[,1]))
    MCtab<-as.data.frame(table(Matches[,2]))
    
    # Extract the matches in which both the reference feature and candidate 
    # feature are real original features
    TrueMatches<-Matches[(Matches[,1]%in%ReferenceList)&
                           (Matches[,2]%in%CandidateList),,drop=FALSE]
    # Extract the addition hallucinations i.e. all the matched features which were
    # not in the original lists
    AHallucinations<-c(Matches[!(Matches[,1]%in%ReferenceList),1],
                       Matches[!(Matches[,2]%in%CandidateList),2])
    
    # initialize empty vectors for the indices in which multi-match hallucinations
    # occur...
    Hindices<-c()
    # ...and for the hallucinations themselves
    MHallucinations<-c()
    # loop through the rows of the matches
    if (length(TrueMatches)>0){
      for (Riter in 1:nrow(TrueMatches)){
        feat<-TrueMatches[Riter,1]
        if (MRtab$Freq[MRtab$Var1==feat]>Rtab$Freq[Rtab$ReferenceList==feat]){
          MRtab$Freq[MRtab$Var1==feat]=MRtab$Freq[MRtab$Var1==feat]-1
          MHallucinations<-c(MHallucinations,feat)
          Hindices<-c(Hindices,Riter)
        }
      }
      for (Citer in 1:nrow(TrueMatches)){
        feat<-TrueMatches[Citer,2]
        if (MCtab$Freq[MCtab$Var1==feat]>Ctab$Freq[Ctab$CandidateList==feat]){
          MCtab$Freq[MCtab$Var1==feat]=MCtab$Freq[MCtab$Var1==feat]-1
          MHallucinations<-c(MHallucinations,feat)
          Hindices<-c(Hindices,Citer)
        }
      }
      if (length(Hindices)>0){
        TrueMatches<-TrueMatches[-Hindices,,drop=FALSE]
      }
    }
    
    Hallucinations<-c(AHallucinations,MHallucinations)
    
    precision<-max(nrow(TrueMatches),0,na.rm=TRUE)/length(CandidateList)
    recall<-max(nrow(TrueMatches),0,na.rm=TRUE)/length(ReferenceList)
    f1<-max(2*precision*recall/(precision+recall),0,na.rm=TRUE)
    
    UnmatchedReferenceFeature<-ReferenceList[!(ReferenceList%in%TrueMatches[,1])]
    UnmatchedCandidateFeature<-CandidateList[!(CandidateList%in%TrueMatches[,2])]
    
    result<-list(TrueMatches=TrueMatches,Hallucinations=Hallucinations,
                 UnmatchedReferenceFeature=UnmatchedReferenceFeature,
                 UnmatchedCandidateFeature=UnmatchedCandidateFeature,
                 precision=precision,recall=recall,f1=f1)
    
    return(result)
  }
  
  # Function to format JSON components
  format_json <- function(json) {
    header_map <- list(
      "TrueMatches" = "True Matches: <span style='font-size: 0.85em; color: gray;'>Pairs of matched features</span>",
      "Hallucinations" = "Hallucinations: <span style='font-size: 0.85em; color: gray;'>Matched features where feature is not in original feature list or is matched multiple times</span>",
      "UnmatchedReferenceFeature" = "Unmatched Reference Features: <span style='font-size: 0.85em; color: gray;'>Expected but unmatched reference features</span>",
      "UnmatchedCandidateFeature" = "Unmatched Candidate Features: <span style='font-size: 0.85em; color: gray;'>Generated features with no matches</span>",
      "precision" = "Precision: <span style='font-size: 0.85em; color: gray;'>Proportion of correct matches</span>",
      "recall" = "Recall: <span style='font-size: 0.85em; color: gray;'>Proportion of relevant features retrieved</span>",
      "f1" = "F1 Score: <span style='font-size: 0.85em; color: gray;'>Harmonic mean of precision and recall</span>"
    )
    
    
    formatted_strings <- c()
    
    for (name in names(json)) {
      # Use header_map to get the display name
      display_name <- header_map[[name]]
      if (is.null(display_name)) {
        display_name <- name  # Fallback if the key is not in the header_map
      }
      
      formatted_strings <- c(
        formatted_strings,
        paste0("<strong>", display_name, "</strong><br>")
      )
      
      if (name == "TrueMatches" && is.matrix(json[[name]])) {
        # Special handling for matched features
        list_items <- apply(json[[name]], 1, function(row) paste(row[1], row[2], sep = ": "))
        formatted_strings <- c(
          formatted_strings,
          paste0("<ul><li>", paste(list_items, collapse = "</li><li>"), "</li></ul>")
        )
      } else if (is.matrix(json[[name]])) {
        # Handle other matrices
        for (i in 1:nrow(json[[name]])) {
          row_items <- paste0("<li>", json[[name]][i, ], collapse = "</li><li>")
          formatted_strings <- c(
            formatted_strings,
            paste0("<ul><li>", row_items, "</li></ul>")
          )
        }
      } else {
        # Handle vectors
        list_items <- paste0("<li>", json[[name]], "</li>")
        formatted_strings <- c(
          formatted_strings,
          paste0("<ul>", list_items, "</ul>")
        )
      }
      
      formatted_strings <- c(formatted_strings, "<br>")
    }
    
    # Combine all parts into a single string
    paste(formatted_strings, collapse = "")
  }
  
  
  add_backticks <- function(s) {
    # s might be something like "Age, BMI, Coexisting Disease"
    
    # 1. Split by commas
    parts <- unlist(strsplit(s, ","))
    # 2. Trim extra spaces
    parts <- trimws(parts)
    # 3. Wrap each piece in backticks
    parts <- paste0("`", parts, "`")
    # 4. Rejoin them with commas
    paste(parts, collapse = ", ")
  }
  
  
  # The evaluation button
  observeEvent(input$evaluation, {
    
    if (trialState() == "No Trial" ||
        ((trialState() %in% c("Custom", "Custom Modified")) && (trialOrigin() == "Custom"))) {
      output$evalResultTextOutput <- renderUI({
        tags$div(
          style = "color: red; font-size: 24px; font-weight: bold; text-align: center; margin-top: 20px;",
          "No valid trial with candidate features exists for evaluation.
          Custom or modified trials can not be validated since the reference features are unknown.
          To perform evaluation return to Step 1 to load an existing NCT ID, generate candidate features in Step 2, and then return to this page."
        )
      })
      return()  # Exit the observer early
    }
    
    eval_model <- "gpt-4-turbo-preview"
    row = CT_Pub_updated.df[CT_Pub_updated.df$NCTId == input$NCTid,]
    #eval_model = input$eval_model
    
    
    promptChoice = 1 #1 for gpt prompts and 2 for llama prompts
    if (startsWith(eval_model, "Meta-")) promptChoice = 2
    
    qstart = get_question_from_row(row)
    # 1. Reference features are already backtick-enclosed in Paper_BaselineMeasures_Corrected
    reference_list <- extract_elements(row["Paper_BaselineMeasures_Corrected"])
    
    # 2. Convert plain-text candidate features to backtick format
    candidate_backtick_string <- add_backticks(input$CandidateFeatures)
    
    # 3. Now parse them with extract_elements(), which looks for `...`
    
    candidate_list <- extract_elements(candidate_backtick_string)
    #candidate_list <- extract_elements(input$CandidateFeatures)
    #produce evaluation prompt based on evaluator LLM choice
    eval_prompts = build_eval_prompt(reference_list, candidate_list, qstart, promptChoice)
    
    systemPrompt(eval_prompts[1])
    evalSystemPrompt(eval_prompts[1])
    prompt = eval_prompts[2]
    evalUserPrompt(prompt)
    
    # Make api call to perform evaluation
    retry = TRUE
    
    withProgress(message = 'Retrieving results from OpenAI', value=0, {
      while(retry){
        tryCatch(
          {
            # model index set to 7 for llama
            matched_json = insistent_create_completion(prompt, eval_model)$choices[[1]]$message$content
            json_data = extract_json(matched_json)
            temp_df = fromJSON(json_data)
            retry = FALSE
          },
          error = function(e) {
            print(as.character(e))
            return()
          })
      }
    })
    
    #remove hallucinations
    matches = temp_df$matched_features
    ReferenceList = extract_elements(CT_Pub_updated.df[CT_Pub_updated.df$NCTId == input$NCTid, "Paper_BaselineMeasures_Corrected"])
    CandidateList = candidate_list
    
    #store cleaned results in reactive var
    cleaned_results = RemoveHallucinations_v2(matches, ReferenceList, CandidateList)
    finalEvalData(cleaned_results)
    
    
    output[[paste0("evalResultTextOutput")]] <- renderUI({
      cr <- finalEvalData()
      
      if (is.null(cr)) {
        return(tags$p(""))
      }
      
      ##
      ## 1. True Matches (Ensure Candidate Feature Data is on Left and Reference Feature Data is on Right)
      trueMatchesUI <- if (!is.null(cr$TrueMatches) && nrow(cr$TrueMatches) > 0) {
        # Convert matches to data frame and ensure at least 2 columns
        matches_df <- as.data.frame(cr$TrueMatches, stringsAsFactors = FALSE)
        
        if (ncol(matches_df) < 2) {
          return(tags$p("Not enough data to display matches."))
        }
        
        # Swap column values (NOT just column names)
        matches_df <- matches_df[, c(2,1)]  # Swap first and second columns
        
        # Rename swapped columns properly
        colnames(matches_df) <- c("Candidate Feature", "Reference Feature")
        
        DT::datatable(
          matches_df,
          options = list(pageLength = 5, searching = FALSE, paging = FALSE,info = FALSE),
          rownames = FALSE
        ) %>%
          DT::formatStyle(
            columns = c("Candidate Feature"),
            backgroundColor = "#FFF6CC",  
            fontWeight = 'bold'
          ) %>%
          DT::formatStyle(
            columns = c("Reference Feature"),
            backgroundColor = "#E1D5F5",  
            fontWeight = 'bold'
          )
      } else {
        tags$p("No true matches found.")
      }
      
      
      ## 2. Unmatched Candidate Features (Now Appears Before Unmatched Reference Features)
      unmatchedCandUI <- if (!is.null(cr$UnmatchedCandidateFeature) &&
                             length(cr$UnmatchedCandidateFeature) > 0) {
        # Create a data frame with exact column name
        cand_df <- data.frame(`Unmatched Candidate Feature` = cr$UnmatchedCandidateFeature,
                              stringsAsFactors = FALSE,
                              check.names = FALSE)
        
        # Render the DataTable with red styling
        DT::datatable(
          cand_df,
          options = list(
            pageLength = 5,
            searching = FALSE,
            paging = FALSE,
            lengthChange = FALSE,
            info = FALSE
          ),
          rownames = FALSE
        ) %>%
          DT::formatStyle(
            columns = "Unmatched Candidate Feature",
            backgroundColor = "#FFF6CC",  # Light coral background
            fontWeight = 'bold'
          )
      } else {
        tags$p("None")
      }
      
      ## 3. Unmatched Reference Features (Now Appears After Unmatched Candidate Features)
      unmatchedRefUI <- if (!is.null(cr$UnmatchedReferenceFeature) &&
                            length(cr$UnmatchedReferenceFeature) > 0) {
        # Create a data frame with exact column name
        ref_df <- data.frame(`Unmatched Reference Feature` = cr$UnmatchedReferenceFeature,
                             stringsAsFactors = FALSE,
                             check.names = FALSE)
        
        # Render the DataTable with blue styling
        DT::datatable(
          ref_df,
          options = list(
            pageLength = 5,
            searching = FALSE,
            paging = FALSE,
            lengthChange = FALSE,
            info = FALSE
          ),
          rownames = FALSE
        ) %>%
          DT::formatStyle(
            columns = "Unmatched Reference Feature",
            backgroundColor = "#E1D5F5",  # Light blue background
            fontWeight = 'bold'
          )
      } else {
        tags$p("None")
      }
      
      ## 4. Scores Calculation (Remains Same)
      scorePrecision <- if (!is.null(cr$precision)) round(cr$precision, 3) else NA
      scoreRecall    <- if (!is.null(cr$recall))    round(cr$recall, 3)    else NA
      scoreF1        <- if (!is.null(cr$f1))        round(cr$f1, 3)        else NA
      
      descCandidateFeatures <- HTML(
        "<span style='font-weight: 600;'>Candidate features are those generated by the LLM in its output.</span>"
      )
      
      descReferenceFeatures <- HTML(
        "<span style='font-weight: 600;'>Reference features are the original (ground truth) features from the dataset or trial.</span>"
      )
      
      descHallucinations <- HTML(
        "<span style='font-weight: 600;'>Hallucinations are features not in either list originally but appeared in the LLM’s output or matching.</span>"
      )
      
      descScores <- HTML(
        paste(
          "<span style='font-weight: 600;'>Precision = number of matches / (number of matches + number of unmatched candidate features)</span>",
          "<span style='font-weight: 600;'>Recall = number of matches / (number of matches + number of unmatched reference features)</span>",
          "<span style='font-weight: 600;'>F1 = (2 * Precision * Recall) / (Precision + Recall)</span>",
          sep = "<br/>"
        )
      )
      
      
      
      # 5. NEW: A separate DataTable for Precision, Recall, and F1 in a different
      # color (lavender) than the other tables (blue, coral, green).
     
      scores_df <- data.frame(
        Metric = c("Precision", "Recall", "F1 Score"),
        Value  = c(scorePrecision, scoreRecall, scoreF1),
        check.names = FALSE,
        stringsAsFactors = FALSE
      )
      
      scoreTableUI <- div(
        style = "width: 300px;",
        
        DT::datatable(
          scores_df,
          options = list(
            pageLength = 5,
            searching = FALSE,
            paging = FALSE,
            lengthChange = FALSE,
            info = FALSE,
            columnDefs = list(
              list(className = 'dt-left', targets = 0:1)  # Force left alignment on both columns (0 and 1)
            )
          ),
          rownames = FALSE
        ) %>%
          DT::formatStyle(
            columns = c("Metric", "Value"),
            backgroundColor = "#CCCCCC",  # Lavender background (or your desired color)
            fontWeight = 'bold'
          )
      )
    
      tagList(
        
        tags$p(HTML(paste0("<strong>Reference Trial NCT ID:</strong> ", input$NCTid))),
        
        # True Matches Section (Candidate on Left, Reference on Right)
        tags$strong("True Matches"),
        tags$p(HTML("<span style='font-weight: 600;'>Pairs of candidate features and reference features that the LLM deemed semantically similar.</span>")),
        
        trueMatchesUI,
        tags$br(),
        
        # Unmatched Candidate Features (Now Above Unmatched Reference Features)
        tags$strong("Unmatched Candidate Features"),
        tags$p(descCandidateFeatures),
        unmatchedCandUI,
        tags$br(),
        
        # Unmatched Reference Features (Now Below Unmatched Candidate Features)
        tags$strong("Unmatched Reference Features"),
        tags$p(descReferenceFeatures),
        unmatchedRefUI,
        tags$br(),
        
        # Scores (Remains Same)
        tags$strong("Evaluation Scores"),
        tags$p(descScores),
        
        # Insert the new table for the metrics:
        scoreTableUI,
        tags$br(),
        
        # Clarify which model generate the baseline feature
        tags$p(paste0("Suggested Baseline Features generated by ", input$model, 
                 ". Evaluation generated by gpt-4o"))
      )
    })
    
  })
  
  # The generate button and the update button is the same button
  observeEvent(c(input$generate, input$update), {
    if (trialState() == "No Trial" ||
        is.null(input$NCTid) ||
        isEmpty(input$Title) ||
        isEmpty(input$BriefSummary) ||
        isEmpty(input$Condition) ||
        (isEmpty(input$InclusionCriteria) && isEmpty(input$ExclusionCriteria)) ||
        isEmpty(input$Intervention) ||
        isEmpty(input$Outcome)) {
      
      output$generateError <- renderUI({
        tags$p("No trial has been specified. Return to Step 1.",
               style = "color: red; font-size: 24px; font-weight: bold; text-align: center; margin-top: 20px;")
      })
      return()  # Stop further processing
    } else {
      output$generateError <- renderUI({ NULL })
    }
    generatedNCTid(input$NCTid)
    generatedTitle(input$Title)
    generatedCandidateFeatures(input$CandidateFeatures)
    # ------------------------
    # 1. Retrieve Example and Target Data
    # ------------------------
    id_eg1 <- input$NCTid_eg1
    id_eg2 <- input$NCTid_eg2
    id_eg3 <- input$NCTid_eg3
    id     <- input$NCTid
    
    selected_eg1 <- CT_Pub_updated.df[CT_Pub_updated.df$NCTId == id_eg1, ]
    selected_eg2 <- CT_Pub_updated.df[CT_Pub_updated.df$NCTId == id_eg2, ]
    selected_eg3 <- CT_Pub_updated.df[CT_Pub_updated.df$NCTId == id_eg3, ]
    selected_row <- CT_Pub_updated.df[CT_Pub_updated.df$NCTId == id, ]
    
    # Check for duplicate IDs.
    if (input$ThreeShotCheck && length(unique(c(input$NCTid, selected_eg1$NCTId, selected_eg2$NCTId, selected_eg3$NCTId))) < 4) {
      output$error_message_three_Report <- renderUI({
        tags$p("Duplicate NCT IDs selected. Choose unique values.",
               style = "color: red; font-size: 24px; font-weight: bold; text-align: center; margin-top: 20px;")
      })
      output$error_message_three_Options <- renderUI({
        span("Duplicate NCT IDs selected. Choose unique values.",
             style = "color: red; font-weight: bold;")
      })
      output$result_text <- renderText({ "" })
      return()
    } else {
      output$error_message_three_Report <- renderUI({ span("") })
      output$error_message_three_Options <- renderUI({ span("") })
      
      # For examples, always use loaded data:
      Title_1               <- selected_eg1$BriefTitle
      BriefSummary_1        <- selected_eg1$BriefSummary
      Condition_1           <- selected_eg1$Conditions
      EligibilityCriteria_1 <- selected_eg1$EligibilityCriteria
      Intervention_1        <- selected_eg1$Interventions
      Outcome_1             <- selected_eg1$PrimaryOutcomes
      Answer_1              <- selected_eg1$Paper_BaselineMeasures_Corrected
      
      Title_2               <- selected_eg2$BriefTitle
      BriefSummary_2        <- selected_eg2$BriefSummary
      Condition_2           <- selected_eg2$Conditions
      EligibilityCriteria_2 <- selected_eg2$EligibilityCriteria
      Intervention_2        <- selected_eg2$Interventions
      Outcome_2             <- selected_eg2$PrimaryOutcomes
      Answer_2              <- selected_eg2$Paper_BaselineMeasures_Corrected
      
      Title_3               <- selected_eg3$BriefTitle
      BriefSummary_3        <- selected_eg3$BriefSummary
      Condition_3           <- selected_eg3$Conditions
      EligibilityCriteria_3 <- selected_eg3$EligibilityCriteria
      Intervention_3        <- selected_eg3$Interventions
      Outcome_3             <- selected_eg3$PrimaryOutcomes
      Answer_3              <- selected_eg3$Paper_BaselineMeasures_Corrected
      
      # For the target trial, decide which values to use:
      if (customMode() || trialOrigin() %in% c("Custom") || trialState() %in% c("Custom", "Custom Modified")) {
        finalTitle               <- trialData$Title
        finalBriefSummary        <- trialData$BriefSummary
        finalCondition           <- trialData$Condition
        finalEligibilityCriteria <- trialData$EligibilityCriteria
        finalIntervention        <- trialData$Intervention
        finalOutcome             <- trialData$Outcome
      } else {
        finalTitle               <- selected_row$BriefTitle
        finalBriefSummary        <- selected_row$BriefSummary
        finalCondition           <- selected_row$Conditions
        finalEligibilityCriteria <- selected_row$EligibilityCriteria
        finalIntervention        <- selected_row$Interventions
        finalOutcome             <- selected_row$PrimaryOutcomes
      }
    }
    
    ThreeShotCheck <- isolate(input$ThreeShotCheck)
    
    # ------------------------
    # 2. Compose a Composite System Prompt
    # ------------------------
    if (ThreeShotCheck == TRUE) {
      baseSys <- isolate(input$systemPrompt_Three_shot)
    } else {
      baseSys <- isolate(input$systemPrompt)
    }
    if (input$explain == TRUE) {
      explanationText <- paste(
        "Use bold text for headings and separate each section with a line break for the explanation. 
         Do not include any colon. Example for explanation part:
         **Age**\nAge is a critical factor in type 2 diabetes studies, influencing metabolic control and treatment response. It impacts insulin sensitivity and beta-cell function, essential in evaluating the trial's aim to achieve glycemic control with minimal weight gain. Studies suggest metabolic characteristics and treatment responses vary significantly with age, affecting HbA1c outcomes.\n
         **Sex**\nSex differences affect diabetes pathophysiology and treatment efficacy. Males and females may respond differently to diabetic medications due to hormonal influences, body fat distribution, and lifestyle factors. These differences can significantly impact the trial’s endpoints of glycemic control and weight change.\n
         **BMI**\nAs the trial specifically targets achieving glycemic control with minimal weight gain, BMI is crucial for baselining and monitoring weight change. Obesity is a key component in type 2 diabetes, affecting insulin resistance and drug metabolism, impacting both therapy outcomes and risks.\n
         **HbA1c**\nThe trial’s primary outcome is defined through HbA1c levels, with eligibility specifying patients with levels between 7.5% and 10%. HbA1c at baseline enables comparison in achieving the target of ≤ 7.4%. It directly reflects glucose control over time, crucial for evaluating the interventions' effectiveness.\n
         **Duration of diabetes**\nThis metric can influence treatment responses and risk of complications due to the progressive nature of type 2 diabetes. Longer duration often correlates with more advanced beta-cell dysfunction, influencing the ability to achieve and maintain target HbA1c levels and manage weight.\n
         **Current oral antidiabetic therapy type and dose**\nUnderstanding the type and dose of current therapy provides insight into the baseline level of disease control and helps stratify patients by their potential responsiveness to the interventions (exenatide and insulin glargine). The stability of this treatment for at least three months prior serves to standardize participants' metabolic status at baseline.")
      finalSys <- paste(baseSys, explanationText)
    } else {
      finalSys <- baseSys
    }
    systemPrompt(finalSys)
    
    
    fields <- c(finalTitle, finalBriefSummary, finalCondition, finalEligibilityCriteria, finalIntervention, finalOutcome)
    if ((customMode() || trialOrigin() %in% c("Custom") || trialState() %in% c("Custom", "Custom Modified")) &&
        all(sapply(fields, function(x) { is.null(x) || trimws(x) == "" }))) {
      showNotification("Custom trial fields are empty. Please fill at least one field.", type = "error")
      return()
    }
    # ------------------------
    # 3. Build the Final Prompt
    # ------------------------
    if (ThreeShotCheck == TRUE) {
      prompt <- paste0(
        "##Question: \n\n<Title>", Title_1,
        "\n<Brief Summary>", BriefSummary_1,
        "\n<Condition>", Condition_1,
        "\n<Eligibility Criteria>", EligibilityCriteria_1,
        "\n<Intervention>", Intervention_1,
        "\n<Outcome>", Outcome_1,
        "\n\n##Answer: {", Answer_1, "}",
        
        "\n\n##Question: \n\n<Title>", Title_2,
        "\n<Brief Summary>", BriefSummary_2,
        "\n<Condition>", Condition_2,
        "\n<Eligibility Criteria>", EligibilityCriteria_2,
        "\n<Intervention>", Intervention_2,
        "\n<Outcome>", Outcome_2,
        "\n\n##Answer: {", Answer_2, "}",
        
        "\n\n##Question: \n\n<Title>", Title_3,
        "\n<Brief Summary>", BriefSummary_3,
        "\n<Condition>", Condition_3,
        "\n<Eligibility Criteria>", EligibilityCriteria_3,
        "\n<Intervention>", Intervention_3,
        "\n<Outcome>", Outcome_3,
        "\n\n##Answer: {", Answer_3, "}",
        
        "\n\n##Question: \n\n<Title>", finalTitle,
        "\n<Brief Summary>", finalBriefSummary,
        "\n<Condition>", finalCondition,
        "\n<Eligibility Criteria>", finalEligibilityCriteria,
        "\n<Intervention>", finalIntervention,
        "\n<Outcome>", finalOutcome,
        "\n\n##Answer:"
      )
      
    } else {
      
      # Optionally update UI fields with target values:
      updateTextAreaInput(session, "Title", value = finalTitle)
      updateTextAreaInput(session, "BriefSummary", value = finalBriefSummary)
      updateTextAreaInput(session, "Condition", value = finalCondition)
      updateTextAreaInput(session, "EligibilityCriteria", value = finalEligibilityCriteria)
      updateTextAreaInput(session, "Intervention", value = finalIntervention)
      updateTextAreaInput(session, "Outcome", value = finalOutcome)
      updateTextAreaInput(session, "ActualFeatures", value = selected_row$Paper_BaselineMeasures_Corrected)
      
      if (customMode() || trialOrigin() %in% c("Custom") || trialState() %in% c("Custom", "Custom Modified")) {
        prompt <- paste0(
          "##Question: \n\n<Title>", trialData$Title,
          "\n<Brief Summary>", trialData$BriefSummary,
          "\n<Condition>", trialData$Condition,
          "\n<Eligibility Criteria>", trialData$EligibilityCriteria,
          "\n<Intervention>", trialData$Intervention,
          "\n<Outcome>", trialData$Outcome,
          "\n\n##Answer:"
        )
      } else {
        
        # Optionally update UI fields with target values:
        updateTextAreaInput(session, "Title", value = finalTitle)
        updateTextAreaInput(session, "BriefSummary", value = finalBriefSummary)
        updateTextAreaInput(session, "Condition", value = finalCondition)
        updateTextAreaInput(session, "EligibilityCriteria", value = finalEligibilityCriteria)
        updateTextAreaInput(session, "Intervention", value = finalIntervention)
        updateTextAreaInput(session, "Outcome", value = finalOutcome)
        updateTextAreaInput(session, "ActualFeatures", value = selected_row$Paper_BaselineMeasures_Corrected)
        prompt <- paste0(
          
          "##Question: \n\n<Title>", input$Title,
          "\n<Brief Summary>", input$BriefSummary,
          "\n<Condition>", input$Condition,
          "\n<Eligibility Criteria>", input$EligibilityCriteria,
          "\n<Intervention>", input$Intervention,
          "\n<Outcome>", input$Outcome,
          "\n\n##Answer:"
        )
      }
    }
    
    promptText(prompt)
    resultText("")    # Clear previous results
    evalResultText("")
    finalEvalData(NULL)
    updateTextAreaInput(session, "CandidateFeatures", value = "")
    output$evalResultTextOutput <- renderUI({ NULL })
    # ------------------------
    # 4. Model Call and Output Processing
    # ------------------------
    modelText(isolate(input$model))
    modelText.tmp <- modelText()
    
    result.short <- list()
    withProgress(message = 'Retrieving results from OpenAI or Meta', value = 0, {
      for (model in modelText()) {
        result <- insistent_create_completion(prompt, model)
        result.short <- list.append(result.short, paste0("[", model, "] ", result$choices[[1]]$message$content))
        resultText(unlist(result.short))
        incProgress(1 / length(isolate(resultText())))
      }
    })
    
    candidate_features <- sub(".*\\{([^}]*)\\}.*", "\\1", resultText())
    candidate_features <- sub("\\n+$", "", candidate_features)
    candidate_features <- sub("^\\s+", "", candidate_features)
    updateTextAreaInput(session, "CandidateFeatures", value = candidate_features)
  },
  ignoreInit = TRUE)
  
  generatedNCTid <- reactiveVal()
  generatedTitle <- reactiveVal()
  generatedCandidateFeatures <- reactiveVal()
  
  # Update result textbox
  output$resultTextOutput <- renderUI({
    if (nchar(resultText()[1]) == 0) return (NULL)
    if (length(resultText()) > 0 && !is.na(resultText()[1])) {
      # Track if Custom or Load
      if (trialState() %in% c("Custom", "Custom Modified")) {
        nct_text <- "<strong>Reference NCT ID:</strong> Custom trial"
      } else if (trialState() %in% c("Loaded", "Modified")) {
        nct_text <- paste0("<strong>NCT ID:</strong> ", generatedNCTid())
      } else {
        nct_text <- "<strong>NCT ID:</strong> (No trial)"}
      
      # Title
      title_text     <- paste0("<strong>Title:</strong> ", generatedTitle())
      # Suggested Features
      features_text  <- paste0("<strong>Suggested Features:</strong> ", "{", input$CandidateFeatures, "}")
      # Get ready for report
      full_llm_output <- resultText()[1]
      explanations_only <- sub("^\\[.*?\\]\\s*\\{[^}]*\\}", "", full_llm_output)
      explanations_only <- trimws(explanations_only)
      explanations_only_formated <- formatStructuredText(explanations_only)
      
      if (input$ThreeShotCheck) {
        # If three-shot is checked
        shot_text <- paste0(
          "Generated by ", input$model, " using three-shot learning (",
          input$NCTid_eg1, ", ",
          input$NCTid_eg2, ", ",
          input$NCTid_eg3, ")."
        )
      } else {
        # If three-shot is NOT checked
        shot_text <- paste0("Generated by ", input$model, " using zero-shot.")
      }
      
      if (input$explain) {
        explanation_text <- paste0("Explanations generated by ", input$model, ".")
        result_content <- paste0("<strong>Explanation:</strong> ", explanations_only_formated)
      } else {
        explanation_text <- paste0("To generate explanations, change options.")
        result_content <- ""
      }
      
      HTML(
        paste0(
          '<div style="background-color:#f8f9f9; padding:10px;">',
          nct_text, "<br/>",
          title_text, "<br/>",
          features_text, "<br/>",
          result_content,
          "<strong>", shot_text, "</strong><br/>",
          "<strong>", explanation_text, "</strong>",
          "</div>"
        )
      )
    }
  })
  
  output$resultTextOutput_evaluate <- renderUI({
    if (length(resultText_evaluate()) > 0 && !is.na(resultText_evaluate()[1])) {
      formatted_text <- formatStructuredText(resultText_evaluate()[1])
      HTML(paste0('<span style="background-color:#f8f9f9;"><b>Evaluation Result:</b> ', formatted_text, '</span>'))
    }
  })
  
  formatStructuredText <- function(raw_text) {
    # Remove any sequences of 3 or more hyphens (and surrounding whitespace)
    raw_text <- gsub("\\s*-{2,}\\s*", " ", raw_text)
    # Split raw text by '**' to find important sections and labels
    parts <- unlist(strsplit(raw_text, "\\*\\*"))
    if (length(parts) < 2) return(raw_text)  # Return raw text if no formatting markers are found
    # Initialize an empty string for structured text
    structured_text <- "<br/>"
    
    # Iterate through parts to add formatting based on label and content
    for (i in seq(2, length(parts), by = 2)) {
      
      # Safely retrieve feature name and explanation
      feature_name <- trimws(parts[i])
      explanation  <- if (i + 1 <= length(parts)) trimws(parts[i + 1]) else ""
      
      # Add curly braces around the feature name, plus extra <br> for spacing
      structured_text <- paste0(
        structured_text,
        "<strong>", feature_name, "</strong>",
        "<br>",
        explanation,
        "<br>"
      )
    }
    
    return(structured_text)
  }
  
  # TODO: Update output.txt
  
  # Not used  
  output$jsonTextOutput <- renderText({
    text <- gsub("\n","<br>",toString(rest.json()))
    text <- gsub(" ","&nbsp;",text)
    HTML(text)
  })
  
  # Implements download handler
  output$downloadData01 <- downloadHandler(
    filename <- function() {
      # The download file name
      paste("CTSuggest-graph-", Sys.Date(), "-", format(Sys.time(), '%H-%M-%S'),".json", sep="")
    },
    
    content <- function(file) {
      # The file from the filesystem
      file.copy("output.json", file)
    }
  )
  
  # Implements download handler
  
  # The download button in 'Step 1'
  output$downloadData_trial <- downloadHandler(
    filename <- function() {
      # The download file name
      paste("CTSuggest-json-", Sys.Date(), "-", format(Sys.time(), '%H-%M-%S'),".json", sep="")
    },
    
    content <- function(file) {
      # Create outputText
      # NOTE: Text formatted as JSON
      outputText <- '{\n'
      outputText <- paste0(outputText,'"Filename": "',filename(),'",\n')
      outputText <- paste0(outputText, '"TrialState": "', trialState(), '",\n')
      outputText <- paste0(outputText,'"Prompts": [\n')
      
      if (trialOrigin() == "Loaded") {
        outputText <- paste0(outputText,
                             '"NCTid": "', gsub('\n', ' ', gsub('"', "'", input$NCTid)), '",\n')
      } else if (trialOrigin() == "Custom") {
        outputText <- paste0(outputText, '"NCTid": "Custom Trial",\n')
      }
      
      outputText <- paste0(outputText,
                           '"Title": "',
                           gsub('\n', ' ', gsub('"', "'", input$Title)),'",\n',
                           '"Summary": "',
                           gsub('\n', ' ', gsub('"', "'", input$BriefSummary)),'",\n', 
                           '"Condition": "',
                           gsub('\n', ' ', gsub('"', "'", input$Condition)),'",\n',
                           '"Eligibility Criteria": "',
                           gsub('\n', ' ', gsub('"', "'", trialData$EligibilityCriteria)),'",\n',
                           '"Intervention": "',
                           gsub('\n', ' ', gsub('"', "'", input$Intervention)),'",\n', 
                           '"Outcome": "',
                           gsub('\n', ' ', gsub('"', "'", input$Outcome)),'"')
      
      if (trialOrigin() == "Loaded") {
        outputText <- paste0(outputText, ',\n',
                             '"Actual Features": "', gsub('\n', ' ', gsub('"', "'", trialData$ActualFeatures)), '"\n')
      } else {
        outputText <- paste0(outputText, "\n")
      }
      outputText <-paste0(outputText, ']')
      outputText <-paste0(outputText, '}')
      writeLines(paste(outputText, collapse = "\n"), file)
    }
  )
  
  # The download button in 'Step 2', check if it is Three-shot
  # Three-shot and Zero-shot download different thing
  output$downloadData_generate <- downloadHandler(
    filename <- function() {
      # The download file name
      paste("CTSuggest-json-", Sys.Date(), "-", format(Sys.time(), '%H-%M-%S'),".json", sep="")
    },
    
    content <- function(file) {
      if (trialState() %in% c("Custom", "Custom Modified")) {
        nct_text <- "Custom trial"
      } else if (trialState() %in% c("Loaded", "Modified")) {
        nct_text <- paste0(generatedNCTid())
      } else {
        nct_text <- "NCT ID: (No trial)"}
      
      # Title
      title_text     <- paste0(generatedTitle())
      # Suggested Features
      features_text  <- paste0("{", input$CandidateFeatures, "}")
      # Get ready for report
      full_llm_output <- resultText()[1]
      explanations_only <- sub("^\\[.*?\\]\\s*\\{[^}]*\\}", "", full_llm_output)
      explanations_only <- trimws(explanations_only)
      explanations_only_formated <- formatStructuredText(explanations_only)
      
      if (input$ThreeShotCheck) {
        # If three-shot is checked
        shot_text <- paste0(
          "Generated by ", input$model, " using three-shot learning (",
          input$NCTid_eg1, ", ",
          input$NCTid_eg2, ", ",
          input$NCTid_eg3, ")."
        )
      } else {
        # If three-shot is NOT checked
        shot_text <- paste0("Generated by ", input$model, " using zero-shot.")
      }
      
      if (input$explain) {
        explanation_text <- paste0("Explanations generated by ", input$model, ".")
        result_content <- paste0(explanations_only_formated)
      } else {
        explanation_text <- paste0("No LLM explanation is added.")
        result_content <- ""
      }
      
      # Create outputText
      # NOTE: Text formatted as JSON
      outputText <- '{\n'
      outputText <- paste0(outputText, '"Filename": "',filename(),'",\n')
      outputText <- paste0(outputText, '"TrialState": "', trialState(), '",\n')
      outputText <- paste0(outputText, '"Report": {\n')
      outputText <- paste0(outputText, '"NCT": "', nct_text, '",\n')
      outputText <- paste0(outputText, '"Title": "', title_text, '",\n')
      outputText <- paste0(outputText, '"SuggestedFeatures": "', features_text, '",\n')
      outputText <- paste0(outputText, '"Explanation": "', result_content, '",\n')
      outputText <- paste0(outputText, '"GenerationDetails": "', shot_text, '",\n')
      outputText <- paste0(outputText, '"ExplanationDetails": "', explanation_text, '"\n')
      outputText <- paste0(outputText, '"Prompts": \n')
      
      if (input$ThreeShotCheck == TRUE) {
        outputText <- paste0(outputText,
                             '{\n',
                             '"Reference Example 1": "',
                             gsub('\n', ' ', gsub('"', "'", input$NCTid_eg1)),'",\n',
                             '"Reference Example 2": "',
                             gsub('\n', ' ', gsub('"', "'", input$NCTid_eg2)),'",\n',
                             '"Reference Example 3": "',
                             gsub('\n', ' ', gsub('"', "'", input$NCTid_eg3)),'",\n',
                             '"System": "',
                             gsub('\n', ' ', gsub('"', "'", systemPrompt())),'",\n',
                             '"User": "',
                             gsub('\n', ' ', gsub('"', "'", promptText())),'",\n', 
                             '"Result": "',
                             gsub('\n', ' ', gsub('"', "'", resultText())),'"\n',
                             '}\n')
      } else {
        outputText <- paste0(outputText,
                             '{\n',
                             '"System": "',
                             gsub('\n', ' ', gsub('"', "'", systemPrompt())),'",\n',
                             '"User": "',
                             gsub('\n', ' ', gsub('"', "'", promptText())),'",\n', 
                             '"Result": "',
                             gsub('\n', ' ', gsub('"', "'", resultText())),'"\n',
                             '}\n')
      }
      
      outputText <-paste0(outputText, '}')
      writeLines(paste(outputText, collapse = "\n"), file)
    }
  )
  
  # The download button in 'Step 3'
  output$downloadData_evaluate <- downloadHandler(
    filename = function() {
      paste("CTSuggest-json-", Sys.Date(), "-", format(Sys.time(), '%H-%M-%S'), ".json", sep = "")
    },
    
    content = function(file) {
      results <- finalEvalData()  # Access the stored reactive value
      
      if (is.null(results)) {
        writeLines('{"error": "No data available"}', file)
        return()
      }
      
      outputText <- '{\n'
      outputText <- paste0(outputText, '"Filename": "', filename(), '",\n')
      outputText <- paste0(outputText, '"Trial ID": "', input$NCTid, '",\n')
      outputText <- paste0(outputText, '"TrialState": "', trialState(), '",\n')
      outputText <- paste0(outputText, '"Evaluation Model": "', input$eval_model, '",\n')
      outputText <- paste0(outputText, '"Candidate Features": "', input$CandidateFeatures,'",\n')
      outputText <- paste0(outputText, '"Actual Features": "', trialData$ActualFeatures,'",\n')
      outputText <- paste0(outputText, '"Results": ', jsonlite::toJSON(results, auto_unbox = TRUE), '\n')
      outputText <- paste0(outputText, '"Prompts": \n')
      outputText <- paste0(outputText,
                           '{\n',
                           '"System": "',
                           gsub('\n', ' ', gsub('"', "'", evalSystemPrompt())),'",\n',
                           '"User": "',
                           gsub('\n', ' ', gsub('"', "'", evalUserPrompt())),'"\n',
                           '}\n')
      outputText <- paste0(outputText, '}')
      writeLines(outputText, file)
    }
  )
  
  
  # Build iframe for image panel  
  output$WDFrame <- renderUI({
    # Retrieve the WD page, given an entity link
    theURL <- gsub("http:","https:",gsub("entity","wiki",gsub(">","",gsub("<","",frameURL()[1]))))
    tags$iframe(src=theURL, height=600, width = "100%")
  })
  
  # Build iframe for image panel  
  output$AutodescFrame <- renderUI({
    # Retrieve Autodesc content, given an entity link
    tryCatch({
      # 
      theEntity <- str_split(gsub(">","",gsub("<","",frameURL()[1])), 'Q', simplify = TRUE)[,2]  # Everything after 'Q'
      theURL <- paste0("https://autodesc.toolforge.org/?q=",theEntity,"&links=wikipedia&lang=en&mode=long&format=html&redlinks=reasonator")
      tags$iframe(src=theURL, 
                  height=300, 
                  width = "100%")
    }, error=function(cond) {
      tags$i("Entity has no Wikidata link..")
    })
  })
  
  output$WDFrameURL <- renderText({
    # Display the WD URL
    HTML(frameURL())
  })
  
  output$modelTextOutput <- renderText({
    # Display the model name(s)
    HTML(paste0("Based on: ", paste(modelText(), collapse = ", ")))
  })
  
  output$modelTextOutput_evaluate <- renderText({
    # Display the model name(s)
    HTML(paste0("Based on: ", paste(modelText(), collapse = ", ")))
  })
  
  
  # Default URL
  frameURL <- reactiveVal(NULL)
  
  # React to click in table cell
  observeEvent(input$triplesTableOutput_cells_selected, {
    if (disableRDF() == FALSE) {
      row <- input$triplesTableOutput_cells_selected[1]
      col <- input$triplesTableOutput_cells_selected[2] # col should be 1 or 3; ignore predicate
      
      if (!is.na(row)) {
        # valid row
        if (col==2) { # Predicate col selected
          descriptionText <- data.frame(subject=c(NA),object="predicate .")
          labelText <- tripleTable()$label3[row] 
          frameURL(tripleTable()$subject[row])
          whichCol("predicate")
        } else if (col==3) { # Object col selected
          descriptionText <- description.df() %>% filter(subject==tripleTable()$object[row])
          labelText <- tripleTable()$label2[row] 
          frameURL(tripleTable()$subject[row])
          whichCol("object")
        } else { # Subject column selected
          descriptionText <- description.df() %>% filter(subject==tripleTable()$subject[row])
          labelText <- tripleTable()$label1[row]
          frameURL(tripleTable()$subject[row])
          whichCol("subject")
        }
      } else {
        descriptionText <- description.df() %>% filter(subject==tripleTable()$subject[1])
        labelText <- tripleTable()$label1[1]
        frameURL(tripleTable()$subject[1])
      }
      entityDescription(paste0(labelText, " is a ", descriptionText$object))
    } # End of if()
  })
  
  # Update the triple table
  output$triplesTableOutput <- DT::renderDataTable({
    displayTable <- tripleTable() 
    
    if (disableRDF() == FALSE) {
      # bnodes in the Object column
      bnodeLabels.obj <- displayTable %>%
        filter(grepl('result', object)) %>%
        select(label1, label2) %>% # Keep both label columns
        mutate(label1 = NA)
      
      # bnodes in the Subject column
      bnodeLabels.sub <- displayTable %>%
        filter(grepl('result', subject)) %>%
        select(label1, label2) %>% # Keep both label columns
        mutate(label2 = NA) 
      
      bnodeLabels <- rbind(bnodeLabels.sub, bnodeLabels.obj)
      
      displayTable <- displayTable %>% 
        rename("Subject"="label1", 
               "Object"="label2",
               "Relationship"="label3",
               "Occurrences"="n") %>%
        dplyr::select(-subject) %>% 
        dplyr::select(-object) %>%
        dplyr::select(-predicate) %>%
        dplyr::distinct()
      
      if (nrow(bnodeLabels)!= 0) {
        datatable(displayTable, 
                  selection = list(mode = "single", target = "cell")) %>%
          formatStyle('Subject', backgroundColor = styleEqual(bnodeLabels$label1,c('#C0C0C0'))) %>%
          formatStyle('Object', backgroundColor = styleEqual(bnodeLabels$label2,c('#C0C0C0')))
      } else {
        datatable(displayTable, 
                  selection = list(mode = "single", target = "cell")) 
      }
      
    } # End of if()
  })
  
  query_modal <- modalDialog(
    title = "Welcome to CTSuggest:  Clinical Trial Suggestion of Baseline Features!",
    "The CTSuggest App aims to provide suggestions of baseline descriptors to clinical 
trial designers using large language models. NOTE: This application is the result of 
the efforts of students. It is presented here 
to showcase the talents of the students. This application may not meet all of the standards 
one might expect of a production commercial product.",
    easyClose = F,
    footer = tagList(actionButton("run", "Continue with CTSuggest"))
  )
  showModal(query_modal)
  observeEvent(input$run, {
    removeModal()
  })
  
}

# Run the application
shinyApp(ui = ui, server = server)
