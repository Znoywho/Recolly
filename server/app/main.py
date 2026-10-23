from app.db.base import Base
from app.db.session import SessionLocal, engine
from app.repository.user_repository import User, UserRepository

if __name__ == "__main__":
    
    Base.metadata.create_all(engine)
    # create database table
    with SessionLocal() as session:
        userRepo = UserRepository(session)
        user = User()
        user.email = "1212"
        userRepo.create(user)
