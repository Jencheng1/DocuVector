from typing import List, Dict, Any, Optional
from langchain.agents import Tool, AgentExecutor, LLMSingleActionAgent
from langchain.chains import SequentialChain, RouterChain
from langchain.memory import ConversationBufferMemory, ConversationBufferWindowMemory
from langchain.prompts import PromptTemplate
from langchain.schema import AgentAction, AgentFinish
from langchain.tools import BaseTool
from langchain.vectorstores import Pinecone
import pinecone
import boto3
import logging

class CustomTool(BaseTool):
    name = "vector_search"
    description = "Search for similar documents in the vector database"
    
    def _run(self, query: str) -> str:
        try:
            vector_store = Pinecone.from_existing_index(
                "docuvector-index",
                self.embeddings
            )
            results = vector_store.similarity_search(query, k=3)
            return "\n".join([doc.page_content for doc in results])
        except Exception as e:
            logging.error(f"Error in vector search: {e}")
            return "Error performing vector search"

class DocumentProcessorTool(BaseTool):
    name = "process_document"
    description = "Process and extract information from documents"
    
    def _run(self, document_path: str) -> str:
        try:
            # Implement document processing logic
            return "Document processed successfully"
        except Exception as e:
            logging.error(f"Error processing document: {e}")
            return "Error processing document"

class AdvancedChainManager:
    def __init__(self, llm, embeddings):
        self.llm = llm
        self.embeddings = embeddings
        self.memory = ConversationBufferWindowMemory(
            k=5,
            return_messages=True
        )
        
    def create_sequential_chain(self):
        """Create a sequential chain for document processing"""
        chain1 = LLMChain(
            llm=self.llm,
            prompt=PromptTemplate(
                input_variables=["document"],
                template="Extract key information from: {document}"
            ),
            output_key="extracted_info"
        )
        
        chain2 = LLMChain(
            llm=self.llm,
            prompt=PromptTemplate(
                input_variables=["extracted_info"],
                template="Summarize the following information: {extracted_info}"
            ),
            output_key="summary"
        )
        
        return SequentialChain(
            chains=[chain1, chain2],
            input_variables=["document"],
            output_variables=["summary"]
        )
        
    def create_router_chain(self):
        """Create a router chain for different types of queries"""
        return RouterChain(
            destination_chains={
                "vector_search": self.create_vector_search_chain(),
                "document_processing": self.create_document_processing_chain()
            },
            default_chain=self.create_default_chain()
        )
        
    def create_agent(self):
        """Create a custom agent with tools"""
        tools = [
            CustomTool(embeddings=self.embeddings),
            DocumentProcessorTool()
        ]
        
        agent = LLMSingleActionAgent(
            llm_chain=self.create_agent_chain(),
            allowed_tools=[tool.name for tool in tools],
            stop=["\nObservation:"]
        )
        
        return AgentExecutor.from_agent_and_tools(
            agent=agent,
            tools=tools,
            memory=self.memory,
            verbose=True
        )
        
    def create_agent_chain(self):
        """Create the agent's LLM chain"""
        return LLMChain(
            llm=self.llm,
            prompt=PromptTemplate(
                input_variables=["input", "agent_scratchpad"],
                template="""
                You are an AI assistant specialized in document processing and information retrieval.
                Use the available tools to help the user.
                
                Input: {input}
                {agent_scratchpad}
                """
            )
        )
        
    def create_vector_search_chain(self):
        """Create chain for vector search operations"""
        return LLMChain(
            llm=self.llm,
            prompt=PromptTemplate(
                input_variables=["query"],
                template="Search for similar documents: {query}"
            )
        )
        
    def create_document_processing_chain(self):
        """Create chain for document processing"""
        return LLMChain(
            llm=self.llm,
            prompt=PromptTemplate(
                input_variables=["document"],
                template="Process the document: {document}"
            )
        )
        
    def create_default_chain(self):
        """Create default chain for unmatched queries"""
        return LLMChain(
            llm=self.llm,
            prompt=PromptTemplate(
                input_variables=["input"],
                template="I don't have a specific chain for this query. Here's a general response: {input}"
            )
        ) 