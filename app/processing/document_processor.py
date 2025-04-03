from typing import List, Dict, Any
import os
from langchain.document_loaders import PyPDFLoader, Docx2txtLoader
from langchain.text_splitter import RecursiveCharacterTextSplitter
from langchain.embeddings import OpenAIEmbeddings
from langchain.vectorstores import Pinecone
import pinecone
from dotenv import load_dotenv

load_dotenv()

class DocumentProcessor:
    def __init__(self):
        self.embeddings = OpenAIEmbeddings()
        self.text_splitter = RecursiveCharacterTextSplitter(
            chunk_size=1000,
            chunk_overlap=200
        )
        
        # Initialize Pinecone
        pinecone.init(
            api_key=os.getenv("PINECONE_API_KEY"),
            environment=os.getenv("PINECONE_ENVIRONMENT")
        )
        
        # Create or get the index
        self.index_name = "document-embeddings"
        if self.index_name not in pinecone.list_indexes():
            pinecone.create_index(
                name=self.index_name,
                dimension=1536,  # OpenAI embedding dimension
                metric="cosine"
            )
        
        self.vector_store = Pinecone.from_existing_index(
            index_name=self.index_name,
            embedding=self.embeddings
        )

    def process_document(self, file_path: str) -> List[Dict[str, Any]]:
        """Process a document and store its embeddings in the vector database."""
        # Load document based on file type
        if file_path.endswith('.pdf'):
            loader = PyPDFLoader(file_path)
        elif file_path.endswith('.docx'):
            loader = Docx2txtLoader(file_path)
        else:
            raise ValueError(f"Unsupported file type: {file_path}")

        # Load and split the document
        documents = loader.load()
        texts = self.text_splitter.split_documents(documents)

        # Store embeddings in Pinecone
        self.vector_store.add_documents(texts)

        return [{
            "text": doc.page_content,
            "metadata": doc.metadata
        } for doc in texts]

    def search_documents(self, query: str, k: int = 5) -> List[Dict[str, Any]]:
        """Search for relevant documents using semantic search."""
        results = self.vector_store.similarity_search(query, k=k)
        return [{
            "text": doc.page_content,
            "metadata": doc.metadata,
            "score": doc.metadata.get("score", 0)
        } for doc in results]

    def delete_document(self, document_id: str) -> bool:
        """Delete a document from the vector database."""
        try:
            self.vector_store.delete([document_id])
            return True
        except Exception as e:
            print(f"Error deleting document: {e}")
            return False 