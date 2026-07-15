# Security policy

Não devem ser adicionados ao repositório:

- arquivos .env reais;
- chaves privadas;
- certificados privados de laboratório;
- tokens OAuth ou JWT;
- senhas ou client secrets;
- bancos de dados de execução;
- binários compilados;
- logs completos que contenham cabeçalhos Authorization.

Antes de cada publicação, deve ser executada uma varredura por segredos
e arquivos binários.
