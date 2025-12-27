FROM continuumio/miniconda3:latest

# Copy environment file and create conda environment
COPY environment.yml .
RUN conda env create -f environment.yml && \
    conda clean -afy

# Set the conda environment
ENV PATH=/opt/conda/envs/webhook/bin:$PATH

# Copy function code
COPY lambda.py ${LAMBDA_TASK_ROOT}/

# Set the CMD to your handler
ENTRYPOINT ["/opt/conda/envs/webhook/bin/python", "-m", "awslambdaric"]
CMD ["lambda.handler"]
