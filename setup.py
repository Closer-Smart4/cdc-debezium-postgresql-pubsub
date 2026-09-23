import setuptools

with open("README.md", "r") as fh:
    long_description = fh.read()

setuptools.setup(
    name="PostgerSQL-Debezium-Pub/Sub",
    version="0.6.0",
    author="Ricardo Miranda",
    author_email="mail@ricardoMiranda.com",
    description="PoC for CDC",
    long_description=long_description,
    long_description_content_type="text/markdown",
    packages=setuptools.find_packages(),
    classifiers=[
        "Programming Language :: Python :: 3",
        "License :: OSI Approved :: MIT License",
        "Operating System :: OS Independent",
    ],
    python_requires='>=3.8',
)