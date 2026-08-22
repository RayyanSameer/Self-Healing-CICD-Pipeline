from app import app


def test_index():
    client = app.test_client()
    response = client.get('/')
    assert response.status_code == 200


def test_health():
    client = app.test_client()
    response = client.get('/health')
    assert response.status_code == 200
    assert response.get_json()["status"] == "healthy"


