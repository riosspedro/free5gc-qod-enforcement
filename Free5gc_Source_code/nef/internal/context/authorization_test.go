package context

import (
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v4"
)

const authorizationTestSigningKey = "0123456789abcdef0123456789abcdef"

func createAuthorizationTestToken(
	t *testing.T,
	method jwt.SigningMethod,
	key string,
	expiresAt int64,
) string {
	t.Helper()

	token := jwt.NewWithClaims(
		method,
		jwt.MapClaims{
			"iss":   "nef-oauth",
			"sub":   "test-client",
			"aud":   "nef-client",
			"scope": "qos-control",
			"iat":   time.Now().Unix(),
			"exp":   expiresAt,
		},
	)

	tokenString, err := token.SignedString([]byte(key))
	if err != nil {
		t.Fatalf("could not sign test token: %v", err)
	}

	return tokenString
}

func authorizationTestContext() *NefContext {
	context := &NefContext{}
	context.OAuth2Required = true

	return context
}

func TestAuthorizationCheckValidToken(t *testing.T) {
	t.Setenv(
		"NEF_OAUTH_JWT_SIGNING_KEY",
		authorizationTestSigningKey,
	)

	token := createAuthorizationTestToken(
		t,
		jwt.SigningMethodHS256,
		authorizationTestSigningKey,
		time.Now().Add(time.Hour).Unix(),
	)

	err := authorizationTestContext().AuthorizationCheck(
		"Bearer " + token,
	)

	if err != nil {
		t.Fatalf("valid token was rejected: %v", err)
	}
}

func TestAuthorizationCheckRejectsExpiredToken(t *testing.T) {
	t.Setenv(
		"NEF_OAUTH_JWT_SIGNING_KEY",
		authorizationTestSigningKey,
	)

	token := createAuthorizationTestToken(
		t,
		jwt.SigningMethodHS256,
		authorizationTestSigningKey,
		time.Now().Add(-time.Hour).Unix(),
	)

	err := authorizationTestContext().AuthorizationCheck(
		"Bearer " + token,
	)

	if err == nil {
		t.Fatal("expired token was accepted")
	}
}

func TestAuthorizationCheckRejectsHS512(t *testing.T) {
	t.Setenv(
		"NEF_OAUTH_JWT_SIGNING_KEY",
		authorizationTestSigningKey,
	)

	token := createAuthorizationTestToken(
		t,
		jwt.SigningMethodHS512,
		authorizationTestSigningKey,
		time.Now().Add(time.Hour).Unix(),
	)

	err := authorizationTestContext().AuthorizationCheck(
		"Bearer " + token,
	)

	if err == nil {
		t.Fatal("token using HS512 was accepted")
	}
}

func TestAuthorizationCheckRequiresBearer(t *testing.T) {
	t.Setenv(
		"NEF_OAUTH_JWT_SIGNING_KEY",
		authorizationTestSigningKey,
	)

	token := createAuthorizationTestToken(
		t,
		jwt.SigningMethodHS256,
		authorizationTestSigningKey,
		time.Now().Add(time.Hour).Unix(),
	)

	err := authorizationTestContext().AuthorizationCheck(token)

	if err == nil {
		t.Fatal("token without Bearer prefix was accepted")
	}
}

func TestAuthorizationCheckRequiresSigningKey(t *testing.T) {
	t.Setenv("NEF_OAUTH_JWT_SIGNING_KEY", "")

	err := authorizationTestContext().AuthorizationCheck(
		"Bearer invalid-token",
	)

	if err == nil {
		t.Fatal("token validation worked without a signing key")
	}
}
