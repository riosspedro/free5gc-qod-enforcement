# Sanitização do repositório

Este repositório possui histórico Git novo.

O histórico original não foi importado porque continha chaves privadas,
certificados de laboratório, binários compilados e credenciais fixas.

Foram preservados:

- código-fonte;
- licenças;
- configurações sem segredos;
- correções do SMF;
- correções do NEF;
- testes;
- documentação;
- evidências sanitizadas do enforcement.

Foram removidos:

- diretórios de certificados;
- arquivos key e pem;
- arquivos .env reais;
- binários de build;
- bancos de dados;
- arquivos de execução;
- histórico Git anterior.
