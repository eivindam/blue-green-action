# EKS blue-green deploy

Deploy EKS service with blue-green deployment

## Usage

1. Set up your credentials as secrets in your repository settings using `AWS_REGION`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` and `KUBE_CONFIG` (cat ~/.kube/config | base64)

2. Add the following to your workflow. You could skip the "Get short hash" step and replace version with full hash, tag or whatever.

```yml
- name: Get short hash
  id: hash
  run: echo "::set-output name=sha_short::$(git rev-parse --short HEAD)"
- name: Blue green deploy
    uses: eivindam/blue-green-action@master
  with:
    kube-config: ${{ secrets.KUBE_CONFIG }}
    deployment-name: websocket
    service-name: websocket
    version: ${{ steps.hash.outputs.sha_short }}
    namespace: default
    accepted-restarts: 1
    restart-wait: 15
  env:
    AWS_REGION: ${{ secrets.AWS_REGION }}
    AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
    AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
```
