using System;

namespace Church.Infrastructure
{
    public interface ITenantService
    {
        Guid GetCurrentTenantId();
    }
}
