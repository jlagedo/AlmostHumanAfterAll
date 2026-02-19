# RunPod SSH Setup

Enable password auth for direct TCP (needed for scp/rsync):

1. Open the **web terminal** from the pod dashboard

2. Set root password:
   ```
   passwd root
   ```

3. Edit SSH config:
   ```
   vi /etc/ssh/sshd_config
   ```
   Set:
   - `PasswordAuthentication yes`
   - `PermitRootLogin yes`

4. Restart SSH:
   ```
   service ssh restart
   ```

## File transfer

The proxied SSH (`ssh.runpod.io`) does **not** support scp/rsync. Use direct TCP instead:

```
scp -P <PORT> local_file root@<POD_IP>:/workspace/
```
