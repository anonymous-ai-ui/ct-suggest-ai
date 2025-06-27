FROM rstudio/r-base:4.4.1-noble

LABEL maintainer="John Erickson <erickj4@rpi.edu>"

# system libraries of general use
RUN apt-get update && apt-get install -y --no-install-recommends \
    sudo \
    cmake \
    libharfbuzz-dev \
    libfreetype6-dev \
    libcurl4-gnutls-dev \
    libcairo2-dev \
    libxt-dev \
    libssl-dev \
    libssh2-1-dev \
    libxml2-dev \
    libproj-dev \
    libgdal-dev \
    libudunits2-dev \
    librdf0 \
    librdf0-dev \
    && rm -rf /var/lib/apt/lists/*

## Regular R packages
RUN R -e 'install.packages("dplyr",repos="https://cloud.r-project.org/")'
RUN R -e 'install.packages("DT",repos="https://cloud.r-project.org/")'
RUN R -e 'install.packages("shiny",repos="https://cloud.r-project.org/")'
RUN R -e 'install.packages("remotes",repos="https://cloud.r-project.org/")'
RUN R -e 'remotes::install_github("irudnyts/openai", ref = "r6")'
RUN R -e 'install.packages("RCurl",repos="https://cloud.r-project.org/")'
RUN R -e 'install.packages("rlist",repos="https://cloud.r-project.org/")'
#RUN R -e 'install.packages("redland",repos="https://cloud.r-project.org/")'
#RUN R -e 'install.packages("rdflib",repos="https://cloud.r-project.org/")'
RUN R -e 'install.packages("jsonlite",repos="https://cloud.r-project.org/")'
RUN R -e 'install.packages("tidyr",repos="https://cloud.r-project.org/")'
RUN R -e 'install.packages("stringr",repos="https://cloud.r-project.org/")'
RUN R -e 'install.packages("purrr",repos="https://cloud.r-project.org/")'
RUN R -e 'install.packages("bslib",repos="https://cloud.r-project.org/")'
RUN R -e 'install.packages("shinyjs",repos="https://cloud.r-project.org/")'

# copy the app to the image
RUN mkdir /root/ctsuggest
COPY . /root/ctsuggest

COPY Rprofile.site /usr/lib/R/etc/

EXPOSE 1824

CMD ["R", "-e", "shiny::runApp('/root/ctsuggest')"]
